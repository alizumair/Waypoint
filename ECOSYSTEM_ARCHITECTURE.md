# Waypoint Ecosystem Architecture Specification

Waypoint is a local-first, zero-cloud ecosystem continuity bridge connecting macOS with Android, iOS, Windows, and Linux devices over local Wi-Fi. This document specifies the protocol designs, background service lifecycles, and synchronization engines powering Waypoint's cross-platform continuity modules.

---

## 1. Notification Bridge Protocol

The Notification Bridge intercepts push notifications on companion devices (such as Android) and replicates them in real-time on macOS as first-class system banners and alerts via the `UserNotifications` framework (`UNUserNotificationCenter`).

### 1.1 Android Background Service Architecture
Android isolates notifications behind the `NotificationListenerService` API. Waypoint runs a persistent background listener service declared in `AndroidManifest.xml` with the `BIND_NOTIFICATION_LISTENER_SERVICE` permission.

```
┌─────────────────────────────────┐
│     Android OS Notification     │
└────────────────┬────────────────┘
                 │ onNotificationPosted(sbn)
                 ▼
┌─────────────────────────────────┐
│ WaypointNotificationListener    │  (Filters system spam, ongoing foreground services)
└────────────────┬────────────────┘
                 │ Serializes to JSON Payload
                 ▼
┌─────────────────────────────────┐
│ Waypoint TCP Socket Client      │  (Network.framework / Socket transport)
└────────────────┬────────────────┘
                 │ TCP Stream (Port 53890)
                 ▼
┌─────────────────────────────────┐
│ macOS Waypoint App              │
│ (P2PNetworkManager)             │
└────────────────┬────────────────┘
                 │ Unmarshals JSON & Maps Actions
                 ▼
┌─────────────────────────────────┐
│ UNUserNotificationCenter        │  (Native macOS Alert Banner with Quick Reply)
└─────────────────────────────────┘
```

#### Android Implementation Outline (Kotlin)
```kotlin
class WaypointNotificationService : NotificationListenerService() {
    override fun onNotificationPosted(sbn: StatusBarNotification) {
        // Suppress ongoing non-clearable notifications (e.g. download progress, system status)
        if (!sbn.isClearable) return

        val extras = sbn.notification.extras
        val title = extras.getCharSequence(Notification.EXTRA_TITLE)?.toString() ?: ""
        val text = extras.getCharSequence(Notification.EXTRA_TEXT)?.toString() ?: ""
        val subText = extras.getCharSequence(Notification.EXTRA_SUB_TEXT)?.toString()
        val appName = packageManager.getApplicationLabel(
            packageManager.getApplicationInfo(sbn.packageName, 0)
        ).toString()

        val actions = sbn.notification.actions?.mapIndexed { index, action ->
            NotificationActionPayload(
                actionId = "${sbn.key}_act_$index",
                title = action.title.toString(),
                isReply = action.remoteInputs?.isNotEmpty() == true
            )
        } ?: emptyList()

        val payload = NotificationRelayPayload(
            notificationId = sbn.key,
            packageName = sbn.packageName,
            appName = appName,
            title = title,
            text = text,
            subText = subText,
            postTime = sbn.postTime / 1000.0,
            iconBase64 = extractAppIconBase64(sbn.packageName),
            actions = actions,
            isClearable = sbn.isClearable
        )

        WaypointSocketManager.sendPacket(WaypointPacketType.NOTIFICATION_RELAY, payload)
    }

    override fun onNotificationRemoved(sbn: StatusBarNotification) {
        // Send notification dismissal packet to auto-dismiss on macOS
    }
}
```

### 1.2 JSON Wire Schema
```json
{
  "notificationId": "0|com.whatsapp|1001|null|10123",
  "packageName": "com.whatsapp",
  "appName": "WhatsApp",
  "title": "Alex Walker",
  "text": "Are we still on for the design review at 3 PM?",
  "subText": "Team Sync",
  "postTime": 1793738400.12,
  "iconBase64": "iVBORw0KGgoAAAANSUhEUgAA...",
  "isClearable": true,
  "actions": [
    {
      "actionId": "reply_action_0",
      "title": "Reply",
      "isReply": true
    },
    {
      "actionId": "mark_read_action_1",
      "title": "Mark as Read",
      "isReply": false
    }
  ]
}
```

### 1.3 macOS Native Integration (`UNUserNotificationCenter`)
Upon receipt of the packet:
1. `ContinuityManager` parses the payload into `NotificationRelayPayload`.
2. Registers a dynamic `UNNotificationCategory` identified by `CATEGORY_<packageName>`, attaching `UNTextInputNotificationAction` for inline text replies or `UNNotificationAction` for buttons.
3. Posts the `UNNotificationRequest` to display the banner.
4. When the user types a reply into the macOS banner notification, `userNotificationCenter(_:didReceive:withCompletionHandler:)` dispatches a remote action packet back to the companion device to trigger the Android `RemoteInput` pending intent.

---

## 2. Clipboard Sync Engine

The Clipboard Sync Engine synchronizes text seamlessly between the macOS `NSPasteboard` and Android `ClipboardManager` without any intermediate servers.

### 2.1 Bi-Directional Event Synchronization & Loop Prevention
```
┌─────────────────────────────────┐               ┌──────────────────────────────────┐
│      macOS (NSPasteboard)       │               │     Android (ClipboardManager)   │
└────────────────┬────────────────┘               └────────────────┬─────────────────┘
                 │ Polls changeCount (500ms)                       │ OnPrimaryClipChangedListener
                 ▼                                                 ▼
      [ Hash != LastSeen ]                              [ Hash != LastSeen ]
                 │                                                 │
                 ▼                                                 ▼
        Broadcasts Text                                   Broadcasts Text
                 │                Local TCP Socket                 │
                 └───────────────────────►─────────────────────────┘
```

#### Infinite Loop / Echo Suppression
When Device A sends copied text $T$ to Device B:
1. Device A computes $H = \text{hash}(T)$ and records $H$ in a FIFO Tombstone Ring Buffer of size $K=32$.
2. Device B receives $T$ over the socket.
3. Device B adds $H = \text{hash}(T)$ to its local Tombstone Ring Buffer before writing $T$ to the system pasteboard.
4. When Device B's local clipboard watcher fires due to the new pasteboard contents, it computes $\text{hash}(T)$.
5. Since $H$ exists in the Tombstone Ring Buffer, Device B recognizes the change as an incoming reflection and suppresses re-broadcasting.

### 2.2 Wire Schema (`ClipboardSyncPayload`)
```json
{
  "id": "e6a12b48-3a9d-48b0-8483-490b4d451a99",
  "text": "https://developer.apple.com/documentation/network",
  "timestamp": 1793738402.55,
  "senderId": "macbook-pro-m3-uid",
  "senderName": "Zumair's MacBook Pro"
}
```

---

## 3. Media Control & Metadata Sync

The Media Control Bridge exposes two-way remote playback synchronization:
- Remote playback state (track title, artist, album, duration, playback position) is streamed to macOS.
- Native media keys (Play, Pause, Next, Previous, Volume) dispatched from macOS control media sessions on mobile devices and vice-versa.

### 3.1 Android MediaSession Integration
Android uses `MediaSessionManager.addOnActiveSessionsChangedListener` to observe active media players (Spotify, YouTube, Pocket Casts).

```kotlin
val sessionManager = getSystemService(Context.MEDIA_SESSION_SERVICE) as MediaSessionManager
val component = ComponentName(this, WaypointNotificationService::class.java)

sessionManager.addOnActiveSessionsChangedListener({ controllers ->
    val activeController = controllers?.firstOrNull() ?: return@addOnActiveSessionsChangedListener
    
    activeController.registerCallback(object : MediaController.Callback() {
        override fun onMetadataChanged(metadata: MediaMetadata?) {
            val title = metadata?.getString(MediaMetadata.METADATA_KEY_TITLE) ?: ""
            val artist = metadata?.getString(MediaMetadata.METADATA_KEY_ARTIST) ?: ""
            val album = metadata?.getString(MediaMetadata.METADATA_KEY_ALBUM) ?: ""
            val duration = (metadata?.getLong(MediaMetadata.METADATA_KEY_DURATION) ?: 0L) / 1000.0
            
            val payload = MediaMetadataPayload(
                title = title,
                artist = artist,
                album = album,
                durationSeconds = duration,
                positionSeconds = 0.0,
                isPlaying = activeController.playbackState?.state == PlaybackState.STATE_PLAYING
            )
            WaypointSocketManager.sendPacket(WaypointPacketType.MEDIA_METADATA_SYNC, payload)
        }

        override fun onPlaybackStateChanged(state: PlaybackState?) {
            // Push updated playback position and play/pause state
        }
    })
}, component)
```

### 3.2 macOS Media Command Ingestion
When macOS receives incoming `MediaCommandPayload`:
- Inbound remote commands execute via AppleScript or `MPRemoteCommandCenter` triggers to toggle local system audio.
- Outbound controls triggered from `PopoverView` dispatch packets (`PLAY`, `PAUSE`, `PLAY_PAUSE_TOGGLE`, `NEXT`, `PREVIOUS`, `VOLUME_UP`, `VOLUME_DOWN`) to control companion devices.

---

## 4. Low-Latency Video Streaming Pipeline (For Mirroring)

The Screen Mirroring Pipeline captures the mobile device's display, encodes it using hardware AVC/H.264, and streams raw NAL units over TCP to macOS for direct hardware decoding and zero-copy rendering into an `AVSampleBufferDisplayLayer`.

### 4.1 Android Pipeline: `MediaProjection` to `MediaCodec`
```
┌─────────────────────────────────┐
│     Android MediaProjection     │  (VirtualDisplay at device native resolution)
└────────────────┬────────────────┘
                 │ Surface
                 ▼
┌─────────────────────────────────┐
│     Hardware MediaCodec         │  (MIMETYPE_VIDEO_AVC, Baseline Profile, 60 FPS)
│     (OMX / C2 Hardware)         │  (BITRATE_MODE_CBR, Keyframe interval: 1s)
└────────────────┬────────────────┘
                 │ Elementary H.264 Stream
                 ▼
┌─────────────────────────────────┐
│     NAL Unit Demuxer & Slicer   │  (SPS [0x07], PPS [0x08], IDR [0x05], Non-IDR [0x01])
└────────────────┬────────────────┘
                 │ TCP Stream (Port 53890)
                 ▼
┌─────────────────────────────────┐
│     macOS Waypoint Ingestion    │
│     (VideoStreamingPipeline)    │
└────────────────┬────────────────┘
                 │ Builds CMFormatDescription from SPS/PPS
                 ▼
┌─────────────────────────────────┐
│     CMSampleBuffer Assembly     │  (AVCC 4-byte length prefix + CMBlockBuffer)
└────────────────┬────────────────┘
                 │ Zero-copy enqueue
                 ▼
┌─────────────────────────────────┐
│   AVSampleBufferDisplayLayer    │  (Metal-accelerated hardware compositor)
└─────────────────────────────────┘
```

#### Android Encoder Configuration (Kotlin)
```kotlin
val mediaFormat = MediaFormat.createVideoFormat(MediaFormat.MIMETYPE_VIDEO_AVC, width, height).apply {
    setInteger(MediaFormat.KEY_COLOR_FORMAT, MediaCodecInfo.CodecCapabilities.COLOR_FormatSurface)
    setInteger(MediaFormat.KEY_BIT_RATE, 6_000_000) // 6 Mbps for crisp 1080p
    setInteger(MediaFormat.KEY_FRAME_RATE, 60)
    setInteger(MediaFormat.KEY_I_FRAME_INTERVAL, 1) // 1 second keyframes
    // Ultra-low latency tuning
    setInteger(MediaFormat.KEY_LATENCY, 0)
    setInteger(MediaFormat.KEY_PRIORITY, 0) // Real-time priority
    setInteger(MediaFormat.KEY_PROFILE, MediaCodecInfo.CodecProfileLevel.AVCProfileBaseline)
    setInteger(MediaFormat.KEY_LEVEL, MediaCodecInfo.CodecProfileLevel.AVCLevel4)
}

val encoder = MediaCodec.createEncoderByType(MediaFormat.MIMETYPE_VIDEO_AVC)
encoder.configure(mediaFormat, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
val inputSurface = encoder.createInputSurface()

// Hook VirtualDisplay to inputSurface
virtualDisplay = mediaProjection.createVirtualDisplay(
    "WaypointMirror",
    width, height, dpi,
    DisplayManager.VIRTUAL_DISPLAY_FLAG_AUTO_MIRROR,
    inputSurface, null, null
)
```

### 4.2 macOS Hardware Decoder Pipeline (`AVSampleBufferDisplayLayer`)
In Waypoint on macOS, `VideoStreamingPipeline.swift` manages the decoding graph:
1. **Parameter Set Ingestion:** Incoming packets of type `sps` (0x07) and `pps` (0x08) are captured and passed to:
   ```swift
   CMVideoFormatDescriptionCreateFromH264ParameterSets(
       allocator: kCFAllocatorDefault,
       parameterSetCount: 2,
       parameterSetPointers: [spsBase, ppsBase],
       parameterSetSizes: [sps.count, pps.count],
       nalUnitHeaderLength: 4,
       formatDescriptionOut: &formatDescription
   )
   ```
2. **AVCC Framing:** Video slices (IDR keyframes and non-IDR delta frames) are transformed from Annex-B into AVCC format by prepending a 4-byte big-endian NAL length prefix.
3. **Block Buffer Creation:** Memory is wrapped in `CMBlockBufferCreateWithMemoryBlock`.
4. **Sample Buffer Packaging:** A `CMSampleBuffer` is instantiated with presentation timestamps (`CMSampleTimingInfo`).
5. **Direct Enqueue:** `displayLayer.enqueue(sampleBuffer)` feeds the frame directly to Apple's VideoToolbox hardware decode pipeline and Metal display layer, delivering sub-25ms glass-to-glass latency over local 5GHz Wi-Fi.

---

## 5. Packet Framing Specification

Every over-the-wire packet uses a fixed 10-byte binary header followed by variable-length data:

| Byte Offset | Field | Type | Description |
|---|---|---|---|
| 0 .. 3 | Magic | 4 bytes (`0x57 0x41 0x59 0x50`) | ASCII `"WAYP"` identifier |
| 4 | Version | `UInt8` | Protocol version (`0x01`) |
| 5 | Packet Type | `UInt8` | Message discriminator (see table below) |
| 6 .. 9 | Payload Length | `UInt32` (Big-Endian) | Size of payload data in bytes |
| 10 .. $(10+L)$ | Payload | Bytes | Serialized JSON or binary chunk |

### Message Types
- `0x01`: `Handshake`
- `0x02`: `HandshakeAck`
- `0x03`: `Ping`
- `0x04`: `Pong`
- `0x10`: `FileManifest`
- `0x11`: `FileChunk`
- `0x12`: `FileTransferComplete`
- `0x13`: `FileTransferCancel`
- `0x20`: `ClipboardSync`
- `0x30`: `NotificationRelay`
- `0x40`: `MediaMetadataSync`
- `0x41`: `MediaCommand`
- `0x50`: `VideoNALUnit`
