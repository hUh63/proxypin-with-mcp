package com.network.proxy.plugin

import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.drawable.BitmapDrawable
import android.graphics.drawable.Drawable
import java.io.ByteArrayOutputStream
import androidx.core.graphics.createBitmap

class ProcessInfo(name: CharSequence, packageName: String, icon: ByteArray?, versionName: String?) :
    HashMap<String, Any?>() {
    init {
        put("name", name)
        put("packageName", packageName)
        put("icon", icon)
        put("versionName", versionName)
    }

    fun copy(): ProcessInfo {
        val name = this["name"] as? CharSequence ?: ""
        val packageName = this["packageName"] as? String ?: ""
        val icon = this["icon"] as? ByteArray
        val versionName = this["versionName"] as? String
        val newInfo = ProcessInfo(name, packageName, icon, versionName)
        newInfo.putAll(this)
        return newInfo
    }

    companion object {
        fun create(
            packageManager: PackageManager,
            app: ApplicationInfo,
            withIcon: Boolean = true,
            withVersion: Boolean = false
        ): ProcessInfo {
            val name = packageManager.getApplicationLabel(app)
            val packageName = app.packageName
            val icon =
                if (withIcon) drawableToByteArray(app.loadIcon(packageManager)) else ByteArray(0)
            // versionName 需要一次跨进程 getPackageInfo 调用。逐个应用查询在冷启动
            // （PackageManager 缓存未热）时可能累计到秒级以上，表现为选择应用页面长时间无响应
            // （上游 #783 第 2 条）。列表页并不展示版本号，因此默认不查，仅在需要时显式开启。
            // 部分应用可能没有设置versionName，或在枚举过程中被卸载/更新导致
            // getPackageInfo抛出NameNotFoundException，将导致获取列表操作失败
            val versionName = if (withVersion) {
                try {
                    packageManager.getPackageInfo(app.packageName, 0).versionName ?: ""
                } catch (e: PackageManager.NameNotFoundException) {
                    ""
                }
            } else ""

            return ProcessInfo(name, packageName, icon, versionName)
        }

        private fun drawableToByteArray(drawable: Drawable): ByteArray {
            val bitmap = drawableToBitmap(drawable)
            val stream = ByteArrayOutputStream()
            bitmap.compress(Bitmap.CompressFormat.PNG, 100, stream)
            return stream.toByteArray()
        }

        private fun drawableToBitmap(drawable: Drawable): Bitmap {
            if (drawable is BitmapDrawable) {
                return drawable.bitmap
            }

            // 获取宽度和高度，如果无效则使用默认值 96dp
            var width = drawable.intrinsicWidth
            var height = drawable.intrinsicHeight

            // 如果宽度或高度无效（≤ 0），使用默认的 96 作为大小
            if (width <= 0) width = 96
            if (height <= 0) height = 96

            val bitmap = createBitmap(width, height)
            val canvas = Canvas(bitmap)
            drawable.setBounds(0, 0, canvas.width, canvas.height)
            drawable.draw(canvas)
            return bitmap
        }

    }

}