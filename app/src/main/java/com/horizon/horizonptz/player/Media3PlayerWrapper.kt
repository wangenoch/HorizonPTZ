package com.horizon.horizonptz.player

import android.content.Context
import android.graphics.Color
import android.util.Log
import android.view.View
import android.view.ViewGroup
import android.widget.FrameLayout
import android.widget.TextView
import androidx.annotation.OptIn
import androidx.media3.common.*
import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.DefaultLoadControl
import androidx.media3.exoplayer.DefaultRenderersFactory
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.LoadControl
import androidx.media3.exoplayer.rtsp.RtspMediaSource
import androidx.media3.exoplayer.upstream.DefaultAllocator
import androidx.media3.ui.PlayerView
import androidx.media3.exoplayer.DecoderCounters
import androidx.media3.exoplayer.analytics.AnalyticsListener
import com.horizon.horizonptz.camera.CameraConfig

@OptIn(UnstableApi::class)
class Media3PlayerWrapper(
    private val context: Context,
    private val container: FrameLayout,
    private val onError: () -> Unit
) : PTZPlayer {

    private var player: ExoPlayer? = null
    private var playerView: PlayerView? = null
    private val TAG = "Media3PlayerWrapper"
    
    private var videoDecoderCounters: DecoderCounters? = null

    override fun prepare(config: CameraConfig, statusView: TextView, bgView: View) {
        release()
        
        playerView = PlayerView(context).apply {
            layoutParams = FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT
            )
            useController = false
            setBackgroundColor(Color.TRANSPARENT)
            setShutterBackgroundColor(Color.TRANSPARENT)
        }
        container.addView(playerView)

        val loadControl: LoadControl = DefaultLoadControl.Builder()
            .setAllocator(DefaultAllocator(true, 16 * 1024))
            .setBufferDurationsMs(
                2000, // 增加到 2 秒最小緩衝以應對 TCP 重傳
                10000, // 最大緩衝 10 秒
                1000, // 播放前等待 1 秒數據
                1500
            )
            .setTargetBufferBytes(-1)
            .setPrioritizeTimeOverSizeThresholds(true)
            .build()

        val renderersFactory = DefaultRenderersFactory(context)
            .setExtensionRendererMode(DefaultRenderersFactory.EXTENSION_RENDERER_MODE_ON)

        player = ExoPlayer.Builder(context, renderersFactory)
            .setLoadControl(loadControl)
            .build().also { p ->
                playerView?.player = p
                p.volume = 0f

                val mediaItem = MediaItem.Builder()
                    .setUri(config.rtspUrl)
                    .setLiveConfiguration(MediaItem.LiveConfiguration.Builder()
                        .setTargetOffsetMs(1500) // 增加到 1.5 秒
                        .setMaxPlaybackSpeed(1.2f)
                        .setMinPlaybackSpeed(1.0f)
                        .build())
                    .build()

                val mediaSource = RtspMediaSource.Factory()
                    .setForceUseRtpTcp(config.useTcp)
                    .setDebugLoggingEnabled(true) // 開啟偵錯日誌
                    .setTimeoutMs(10000) // 延長超時到 10 秒
                    .createMediaSource(mediaItem)

                p.setMediaSource(mediaSource)
                
                p.addAnalyticsListener(object : AnalyticsListener {
                    override fun onVideoEnabled(eventTime: AnalyticsListener.EventTime, counters: DecoderCounters) {
                        videoDecoderCounters = counters
                    }
                })

                p.addListener(object : Player.Listener {
                    override fun onPlaybackStateChanged(state: Int) {
                        when (state) {
                            Player.STATE_READY -> {
                                bgView.visibility = View.GONE
                                playerView?.alpha = 1f
                                statusView.text = "● ONLINE"
                                statusView.setTextColor(Color.GREEN)
                            }
                            Player.STATE_BUFFERING -> {
                                statusView.text = "● BUFFERING"
                                statusView.setTextColor(Color.YELLOW)
                            }
                            else -> {
                                bgView.visibility = View.VISIBLE
                                playerView?.alpha = 0f
                            }
                        }
                    }

                    override fun onPlayerError(error: PlaybackException) {
                        Log.e(TAG, "ExoPlayer Error: ${error.errorCodeName}", error)
                        onError()
                    }
                })
                p.prepare()
            }
    }

    override fun play() {
        player?.play()
    }

    override fun stop() {
        player?.stop()
    }

    override fun release() {
        player?.release()
        player = null
        playerView?.let { container.removeView(it) }
        playerView = null
    }

    override fun isPlaying(): Boolean = player?.isPlaying == true

    override fun getBufferedPosition(): Long = player?.bufferedPosition ?: 0L

    override fun getCurrentPosition(): Long = player?.currentPosition ?: 0L
    
    fun setPlaybackSpeed(speed: Float) {
        player?.playbackParameters = PlaybackParameters(speed)
    }

    fun getPlaybackSpeed(): Float = player?.playbackParameters?.speed ?: 1.0f

    fun getVideoStats(): String {
        val counters = videoDecoderCounters ?: return "N/A"
        return "FPS: ${calculateFps(counters)} | DROP: ${counters.droppedBufferCount}"
    }

    private var lastFrameCount = 0
    private var lastTime = 0L

    private fun calculateFps(counters: DecoderCounters): Int {
        val now = System.currentTimeMillis()
        val rendered = counters.renderedOutputBufferCount
        val diffFrame = rendered - lastFrameCount
        val diffTime = now - lastTime
        if (diffTime < 1000) return (diffFrame * 1000 / diffTime.coerceAtLeast(1)).toInt()
        
        lastFrameCount = rendered
        lastTime = now
        return diffFrame
    }
}
