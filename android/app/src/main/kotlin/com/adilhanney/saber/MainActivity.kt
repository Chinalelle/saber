package com.adilhanney.saber

import android.os.Build
import android.os.Bundle
import androidx.core.view.ViewCompat
import androidx.core.view.WindowCompat
import io.flutter.embedding.android.FlutterActivity
import android.content.Intent.FLAG_ACTIVITY_NEW_TASK

class MainActivity: FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        if (intent.getIntExtra("org.chromium.chrome.extra.TASK_ID", -1) == this.taskId) {
            this.finish()
            intent.addFlags(FLAG_ACTIVITY_NEW_TASK);
            startActivity(intent);
        }
        super.onCreate(savedInstanceState)

        WindowCompat.setDecorFitsSystemWindows(window, false)

        val windowInsetsController = WindowCompat.getInsetsController(window, window.decorView)
        windowInsetsController.isAppearanceLightNavigationBars = true

        applyMaxRefreshRate()
    }

    // 让笔记跑在这块屏幕支持的最高刷新率上。
    //
    // 小米平板 9 Pro Max 的面板支持 144Hz，但系统给普通应用的默认档只到 120Hz，
    // 手写跟不跟手基本就取决于这个。取 supportedModes 里最高的那档去请求，
    // 系统不支持时这个调用本身是 no-op。
    private fun applyMaxRefreshRate() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) return
        val currentDisplay = display ?: return
        val maxMode = currentDisplay.supportedModes
            .maxByOrNull { it.refreshRate } ?: return
        @Suppress("DEPRECATION")
        window.attributes = window.attributes.apply {
            preferredDisplayModeId = maxMode.modeId
        }
    }
}
