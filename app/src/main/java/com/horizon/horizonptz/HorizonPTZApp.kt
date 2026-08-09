package com.horizon.horizonptz

import android.app.Application
import com.horizon.horizonptz.camera.CameraRepository
import tv.danmaku.ijk.media.player.IjkMediaPlayer

/**
 * 自定義 Application 類別，用於管理單例物件
 */
class HorizonPTZApp : Application() {

    // 延遲初始化 Repository，確保 context 已就緒
    val repository: CameraRepository by lazy {
        CameraRepository(this)
    }

    override fun onCreate() {
        super.onCreate()
        instance = this
        
        // 暫時註解掉 IJKPlayer 初始化，因為舊版 .so 與 16KB Page Size 系統不相容導致崩潰
        // IjkMediaPlayer.loadLibrariesOnce(null)
        // IjkMediaPlayer.native_profileBegin("libijkplayer.so")
    }

    companion object {
        lateinit var instance: HorizonPTZApp
            private set
    }
}
