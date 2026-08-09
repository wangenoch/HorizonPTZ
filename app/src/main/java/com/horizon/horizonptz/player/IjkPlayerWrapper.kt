package com.horizon.horizonptz.player

import android.content.Context
import android.graphics.Color
import android.view.SurfaceHolder
import android.view.SurfaceView
import android.view.View
import android.view.ViewGroup
import android.widget.FrameLayout
import android.widget.TextView
import tv.danmaku.ijk.media.player.IjkMediaPlayer
import com.horizon.horizonptz.camera.CameraConfig

class IjkPlayerWrapper(
    private val context: Context,
    private val container: FrameLayout,
    private val onError: () -> Unit
) : PTZPlayer {

    private var player: IjkMediaPlayer? = null
    private var surfaceView: SurfaceView? = null

    override fun prepare(config: CameraConfig, statusView: TextView, bgView: View) {
        release()
        
        surfaceView = SurfaceView(context).apply {
            layoutParams = FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT
            )
        }
        container.addView(surfaceView)

        player = IjkMediaPlayer().apply {
            // Low-latency options
            setOption(IjkMediaPlayer.OPT_CATEGORY_PLAYER, "start-on-prepared", 1)
            setOption(IjkMediaPlayer.OPT_CATEGORY_PLAYER, "packet-buffering", 0)
            setOption(IjkMediaPlayer.OPT_CATEGORY_PLAYER, "framedrop", 1)
            setOption(IjkMediaPlayer.OPT_CATEGORY_FORMAT, "rtsp_transport", if (config.useTcp) "tcp" else "udp")
            setOption(IjkMediaPlayer.OPT_CATEGORY_FORMAT, "infbuf", 1)
            setOption(IjkMediaPlayer.OPT_CATEGORY_FORMAT, "analyzemaxduration", 100)
            setOption(IjkMediaPlayer.OPT_CATEGORY_FORMAT, "probesize", 1024)
            setOption(IjkMediaPlayer.OPT_CATEGORY_FORMAT, "flush_packets", 1)
            
            dataSource = config.rtspUrl
            
            surfaceView?.holder?.addCallback(object : SurfaceHolder.Callback {
                override fun surfaceCreated(holder: SurfaceHolder) {
                    setDisplay(holder)
                }
                override fun surfaceChanged(holder: SurfaceHolder, format: Int, w: Int, h: Int) {}
                override fun surfaceDestroyed(holder: SurfaceHolder) {}
            })

            setOnPreparedListener {
                bgView.visibility = View.GONE
                statusView.text = "● ONLINE"
                statusView.setTextColor(Color.GREEN)
                start()
            }

            setOnErrorListener { _, what, extra ->
                onError()
                true
            }
            
            prepareAsync()
        }
    }

    override fun play() {
        player?.start()
    }

    override fun stop() {
        player?.stop()
    }

    override fun release() {
        player?.release()
        player = null
        surfaceView?.let { container.removeView(it) }
        surfaceView = null
    }

    override fun isPlaying(): Boolean = player?.isPlaying == true

    override fun getBufferedPosition(): Long = 0L // IJK doesn't expose this easily in this version

    override fun getCurrentPosition(): Long = player?.currentPosition ?: 0L
}
