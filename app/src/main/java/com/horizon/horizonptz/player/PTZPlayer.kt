package com.horizon.horizonptz.player

import android.widget.TextView
import android.view.View
import com.horizon.horizonptz.camera.CameraConfig

/**
 * Interface for different video player engines.
 */
interface PTZPlayer {
    fun prepare(config: CameraConfig, statusView: TextView, bgView: View)
    fun play()
    fun stop()
    fun release()
    fun isPlaying(): Boolean
    fun getBufferedPosition(): Long
    fun getCurrentPosition(): Long
}
