package com.network.proxy.plugin

import android.annotation.SuppressLint
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.PixelFormat
import android.graphics.RadialGradient
import android.graphics.RectF
import android.graphics.Shader
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.provider.Settings
import android.util.Log
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import android.widget.Button
import android.widget.LinearLayout
import android.widget.TextView

/**
 * 悬浮球前台服务（液态玻璃风格）：
 * - 小巧正圆玻璃球：径向渐变球体 + 顶部高光 + 白色波纹图案，无描边，颜色/透明度可自定义
 * - 拖动跟随手指（屏幕坐标驱动，坐标系与贴边一致），3 秒无操作自动贴边
 * - 点击弹出配置面板：始终出现在球的内侧且不与球重叠（垂直与球心对齐），
 *   内容：设置 / 换颜色 / 调透明度 / 贴边开关 / 隐藏悬浮球（实时写回偏好设置）
 * - 前台服务提升应用保活能力
 */
class FloatingBallService : Service() {
    companion object {
        const val TAG = "FloatingBall"
        const val CHANNEL_ID = "floating-ball"
        const val NOTIFICATION_ID = 9528

        /** 球体直径（dp），小尺寸正圆 */
        const val BALL_DP = 36

        /** 与 Flutter 侧预置色一致的循环列表 */
        val PRESET_COLORS = intArrayOf(
            0xFF6750A4.toInt(), 0xFF1565C0.toInt(), 0xFF2E7D32.toInt(),
            0xFFEF6C00.toInt(), 0xFFC2185B.toInt(), 0xFF37474F.toInt()
        )
        val ALPHA_CYCLE = intArrayOf(255, 220, 185, 150)

        /** 主进程 MCP 状态（由 McpPlugin 写入，保留字段兼容旧调用） */
        @Volatile
        var mcpRunning: Boolean = false
    }

    private lateinit var windowManager: WindowManager
    private var ballView: GlassBallView? = null
    private var panelView: LinearLayout? = null
    private var ballParams: WindowManager.LayoutParams? = null
    private var panelParams: WindowManager.LayoutParams? = null

    private var ballColor = 0xFF6750A4.toInt()
    private var ballAlpha = 255
    private var autoDock = true

    private val handler = Handler(Looper.getMainLooper())
    private var dockRunnable: Runnable? = null
    private var panelOpen = false

    override fun onBind(intent: Intent?): IBinder? = null

    /** 球体像素尺寸 */
    private fun ballSizePx(): Int = (BALL_DP * resources.displayMetrics.density).toInt()

    /** 球左缘的屏幕坐标（窗口 gravity 为 TOP|END，x 表示距右缘距离） */
    private fun ballScreenLeft(): Int {
        val dm = resources.displayMetrics
        return dm.widthPixels - (ballParams?.x ?: 0) - ballSizePx()
    }

    override fun onCreate() {
        super.onCreate()
        windowManager = getSystemService(Context.WINDOW_SERVICE) as WindowManager
        startForeground()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == "STOP") {
            stopSelf()
            return START_NOT_STICKY
        }
        autoDock = intent?.getBooleanExtra("autoDock", true) ?: true
        ballColor = intent?.getIntExtra("color", 0xFF6750A4.toInt()) ?: 0xFF6750A4.toInt()
        ballAlpha = intent?.getIntExtra("alpha", 255) ?: 255

        if (!Settings.canDrawOverlays(this)) {
            Log.w(TAG, "no overlay permission")
            stopSelf()
            return START_NOT_STICKY
        }

        if (ballView == null) {
            createBall()
        } else {
            refreshBallStyle()
        }
        return START_STICKY
    }

    private fun startForeground() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(CHANNEL_ID, "悬浮球", NotificationManager.IMPORTANCE_LOW)
            getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
        }
        val notification = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION") Notification.Builder(this)
        }
            .setContentTitle("ProxyPin 悬浮球")
            .setContentText("悬浮球运行中，点击可快速配置")
            .setSmallIcon(android.R.drawable.ic_menu_manage)
            .build()
        // Android 14+ 要求前台服务带类型（manifest 已声明 specialUse）
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(NOTIFICATION_ID, notification, android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    @SuppressLint("ClickableViewAccessibility")
    private fun createBall() {
        val sizePx = ballSizePx()
        ballView = GlassBallView(this).apply {
            setStyle(ballColor, ballAlpha)
        }

        ballParams = WindowManager.LayoutParams(
            sizePx, sizePx,
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY,
            // FLAG_LAYOUT_NO_LIMITS：允许窗口超出屏幕边界（收纳 2/3 藏入边缘必需，
            // 否则系统会把负坐标 clamp 回屏内导致收纳无效）
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS,
            PixelFormat.TRANSLUCENT
        ).apply {
            gravity = Gravity.TOP or Gravity.END
            x = 24
            // 默认初始位置：屏幕高度约 1/3 处（往下移，不顶在状态栏附近）
            y = (resources.displayMetrics.heightPixels / 3).coerceAtLeast(260)
        }

        val dm = resources.displayMetrics
        var downRawX = 0f; var downRawY = 0f
        var startLeft = 0; var startTop = 0
        var moved = false

        ballView?.setOnTouchListener { _, event ->
            when (event.action) {
                MotionEvent.ACTION_DOWN -> {
                    downRawX = event.rawX; downRawY = event.rawY
                    startLeft = ballScreenLeft()
                    startTop = ballParams?.y ?: 0
                    moved = false
                    cancelDock()
                    wakeFromDock()
                    false
                }
                MotionEvent.ACTION_MOVE -> {
                    val dx = (event.rawX - downRawX).toInt()
                    val dy = (event.rawY - downRawY).toInt()
                    if (dx * dx + dy * dy > 100) {
                        moved = true
                        // 拖动以屏幕坐标驱动，避免 END 坐标系方向反导致球不跟手
                        val newLeft = (startLeft + dx).coerceIn(0, dm.widthPixels - sizePx)
                        val newTop = (startTop + dy).coerceIn(0, dm.heightPixels - sizePx)
                        ballParams?.x = dm.widthPixels - newLeft - sizePx
                        ballParams?.y = newTop
                        ballParams?.let { windowManager.updateViewLayout(ballView, it) }
                    }
                    moved
                }
                MotionEvent.ACTION_UP -> {
                    if (!moved) togglePanel()
                    dockToEdge()
                    if (!panelOpen) scheduleRetract()
                    true
                }
                else -> false
            }
        }

        try {
            windowManager.addView(ballView, ballParams)
        } catch (e: Exception) {
            // 悬浮窗被系统/厂商拦截时必须给出可见反馈，否则用户开启后什么都看不到
            Log.e(TAG, "悬浮球添加失败", e)
            ballView = null
            try {
                android.widget.Toast.makeText(
                    this,
                    "悬浮球启动失败：${e.message ?: "窗口被系统拒绝，请检查「显示悬浮窗」与厂商后台弹出权限"}",
                    android.widget.Toast.LENGTH_LONG
                ).show()
            } catch (_: Throwable) {}
            return
        }
        dockToEdge()
        scheduleRetract()
    }

    private fun refreshBallStyle() {
        ballView?.setStyle(ballColor, ballAlpha)
    }

    /** 将配置写回 Flutter shared_preferences，保证设置页与悬浮球面板状态一致 */
    private fun savePref(key: String, value: Any) {
        try {
            val sp = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            sp.edit().apply {
                when (value) {
                    is Boolean -> putBoolean("flutter.$key", value)
                    is Int -> putLong("flutter.$key", value.toLong())
                    is String -> putString("flutter.$key", value)
                }
            }.commit()
        } catch (e: Exception) {
            Log.w(TAG, "savePref failed: $key", e)
        }
    }

    private fun togglePanel() {
        if (panelOpen) {
            closePanel()
            return
        }
        panelOpen = true
        val dm = resources.displayMetrics
        val density = dm.density

        panelView = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            // 玻璃面板：深色半透明圆角 + 细白描边
            background = GradientDrawable().apply {
                cornerRadius = 22f
                setColor(Color.argb(232, 24, 24, 30))
                setStroke(1, Color.argb(46, 255, 255, 255))
            }
            setPadding((22 * density).toInt(), (16 * density).toInt(), (22 * density).toInt(), (18 * density).toInt())
            elevation = 18f
        }

        val title = TextView(this).apply {
            text = "悬浮球"
            setTextColor(Color.argb(190, 255, 255, 255))
            textSize = 10f
            letterSpacing = 0.08f
        }
        panelView?.addView(title)

        fun addButton(text: String, action: (Button) -> Unit): Button {
            val btn = Button(this).apply {
                this.text = text
                textSize = 11.5f
                isAllCaps = false
                setTextColor(Color.WHITE)
                background = GradientDrawable().apply {
                    cornerRadius = 16f
                    setColor(Color.argb(40, 255, 255, 255))
                    setStroke(1, Color.argb(34, 255, 255, 255))
                }
                layoutParams = LinearLayout.LayoutParams(
                    (132 * density).toInt(),
                    LinearLayout.LayoutParams.WRAP_CONTENT
                ).apply { topMargin = (5 * density).toInt() }
                setPadding(0, 0, 0, 0)
                setOnClickListener { action(this) }
            }
            panelView?.addView(btn)
            return btn
        }

        addButton("MCP 设置") {
            // 拉起应用并跳转 MCP 设置页（MainActivity 转发 intent 给 Flutter 导航）
            val launch = packageManager.getLaunchIntentForPackage(packageName)
            launch?.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
            launch?.putExtra("com.proxy.openMcpSettings", true)
            startActivity(launch)
            closePanel()
        }
        addButton("换颜色") {
            var idx = PRESET_COLORS.indexOf(ballColor)
            idx = (idx + 1) % PRESET_COLORS.size
            ballColor = PRESET_COLORS[idx]
            refreshBallStyle()
            savePref("floatingBallColor", ballColor)
            McpPlugin.notifyFloatingBallConfigChanged(color = ballColor)
        }
        addButton("调透明度") {
            var idx = 0
            var best = Int.MAX_VALUE
            ALPHA_CYCLE.forEachIndexed { i, a -> if (kotlin.math.abs(a - ballAlpha) < best) { best = kotlin.math.abs(a - ballAlpha); idx = i } }
            idx = (idx + 1) % ALPHA_CYCLE.size
            ballAlpha = ALPHA_CYCLE[idx]
            refreshBallStyle()
            savePref("floatingBallAlpha", ballAlpha)
            McpPlugin.notifyFloatingBallConfigChanged(alpha = ballAlpha)
        }
        val dockBtn = addButton(if (autoDock) "贴边：开" else "贴边：关") { btn ->
            autoDock = !autoDock
            btn.text = if (autoDock) "贴边：开" else "贴边：关"
            savePref("floatingBallAutoDock", autoDock)
            McpPlugin.notifyFloatingBallConfigChanged(autoDock = autoDock)
            if (autoDock) scheduleRetract() else cancelDock()
        }
        dockBtn.text = if (autoDock) "贴边：开" else "贴边：关"
        addButton("关闭悬浮球") {
            savePref("floatingBallEnabled", false)
            // 通知 Flutter 同步内存缓存：否则设置页会读到旧的 enabled=true 而重新拉起服务
            McpPlugin.notifyFloatingBallConfigChanged(enabled = false)
            closePanel()
            stopSelf()
        }

        // 面板定位：球在右半屏 → 面板在球左侧；球在左半屏 → 面板在球右侧。
        // 与球保持 16dp 间距不重叠，垂直方向与球心对齐，且面板整体不超出屏幕。
        val sizePx = ballSizePx()
        val ballLeft = ballScreenLeft()
        val ballTop = (ballParams?.y ?: 260)
        val ballCenterY = ballTop + sizePx / 2
        val onLeft = ballLeft + sizePx / 2 < dm.widthPixels / 2
        // 面板估算高度：标题 + 5 个按钮 + padding（dp）
        val panelH = (240 * density).toInt()

        panelParams = WindowManager.LayoutParams(
            WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE,
            PixelFormat.TRANSLUCENT
        ).apply {
            if (onLeft) {
                // 面板在球右侧
                gravity = Gravity.TOP or Gravity.START
                x = (ballLeft + sizePx + (16 * density).toInt())
                    .coerceAtMost(dm.widthPixels - (150 * density).toInt())
            } else {
                // 面板在球左侧：END 系 x = 距右缘距离，面板右缘 = 球左缘 - 16dp
                gravity = Gravity.TOP or Gravity.END
                x = (dm.widthPixels - ballLeft + (16 * density).toInt())
                    .coerceAtMost(dm.widthPixels - (150 * density).toInt())
            }
            // 垂直：面板中心对齐球心，限制在屏内
            y = (ballCenterY - panelH / 2).coerceIn((8 * density).toInt(), dm.heightPixels - panelH - (8 * density).toInt())
        }
        try {
            windowManager.addView(panelView, panelParams)
        } catch (e: Exception) {
            Log.e(TAG, "面板添加失败", e)
            panelOpen = false
            panelView = null
        }
    }

    private fun closePanel() {
        try {
            panelView?.let { windowManager.removeView(it) }
        } catch (_: Exception) {}
        panelView = null
        panelOpen = false
    }

    /** 悬浮球默认吸附屏幕左右边缘（完整可见），拖动/点击后立即吸附 */
    private fun dockToEdge() {
        val params = ballParams ?: return
        val screen = resources.displayMetrics.widthPixels
        val sizePx = ballSizePx()
        // END 系：x 为距右缘距离；球心屏幕坐标 ≈ screen - x - sizePx/2
        val center = screen - params.x - sizePx / 2
        params.x = if (center < screen / 2) screen - sizePx - 8 else 8
        ballView?.let {
            it.docked = false
            it.alpha = ballAlpha.coerceIn(30, 255) / 255f
            try {
                windowManager.updateViewLayout(it, params)
            } catch (_: Exception) {}
        }
    }

    /** 贴边开关开启：3 秒后收纳（藏入边缘 2/3 只露 1/3，透明度降低） */
    private fun scheduleRetract() {
        cancelDock()
        if (!autoDock) return
        dockRunnable = Runnable { retractToEdge() }
        handler.postDelayed(dockRunnable!!, 3000)
    }

    private fun retractToEdge() {
        if (panelOpen) return
        val params = ballParams ?: return
        val screen = resources.displayMetrics.widthPixels
        val sizePx = ballSizePx()
        val center = screen - params.x - sizePx / 2
        params.x = if (center < screen / 2) screen - sizePx / 3 else -(2 * sizePx / 3)
        ballView?.let {
            it.docked = true
            it.alpha = (ballAlpha.coerceIn(30, 255) / 255f) * 0.45f
            try {
                windowManager.updateViewLayout(it, params)
            } catch (_: Exception) {}
        }
    }

    /** 触碰/唤起时从收纳状态恢复：位置拉回屏内、透明度还原 */
    private fun wakeFromDock() {
        val view = ballView ?: return
        if (!view.docked) return
        view.docked = false
        view.alpha = ballAlpha.coerceIn(30, 255) / 255f
        val params = ballParams ?: return
        val dm = resources.displayMetrics
        val sizePx = ballSizePx()
        params.x = if (params.x < 0) 8 else (dm.widthPixels - sizePx - 8).coerceAtLeast(8)
        try {
            windowManager.updateViewLayout(view, params)
        } catch (_: Exception) {}
    }

    private fun cancelDock() {
        dockRunnable?.let { handler.removeCallbacks(it) }
    }

    override fun onDestroy() {
        cancelDock()
        try {
            panelView?.let { windowManager.removeView(it) }
        } catch (_: Exception) {}
        try {
            ballView?.let { windowManager.removeView(it) }
        } catch (_: Exception) {}
        panelView = null
        ballView = null
        super.onDestroy()
    }
}

/**
 * 液态玻璃球视图：
 * - 正圆（View 尺寸固定且宽高相等）
 * - 径向渐变球体（左上高光过渡到主色再到暗部），无描边
 * - 顶部椭圆玻璃高光 + 白色同心波纹图案（圆头描边，渐弱）
 */
private class GlassBallView(context: Context) : View(context) {
    private val paint = Paint(Paint.ANTI_ALIAS_FLAG)
    private var baseColor = 0xFF6750A4.toInt()

    /** 是否处于贴边收纳状态（透明度已降低） */
    var docked = false

    fun setStyle(color: Int, alpha: Int) {
        baseColor = color
        this.alpha = (alpha.coerceIn(30, 255)) / 255f
        invalidate()
    }

    override fun onDraw(canvas: Canvas) {
        val size = width.coerceAtMost(height).toFloat()
        if (size <= 0) return
        val cx = width / 2f
        val cy = height / 2f
        val r = size / 2f

        // 球体：径向渐变（左上亮 → 主色 → 右下暗）
        paint.shader = RadialGradient(
            cx - r * 0.32f, cy - r * 0.38f, r * 1.32f,
            intArrayOf(lighten(baseColor, 0.42f), baseColor, darken(baseColor, 0.38f)),
            floatArrayOf(0f, 0.52f, 1f),
            Shader.TileMode.CLAMP
        )
        canvas.drawCircle(cx, cy, r, paint)

        // 顶部玻璃高光（椭圆白斑）
        paint.shader = null
        paint.style = Paint.Style.FILL
        paint.color = Color.argb(64, 255, 255, 255)
        canvas.drawOval(
            RectF(cx - r * 0.56f, cy - r * 0.82f, cx + r * 0.08f, cy - r * 0.36f),
            paint
        )
        // 底部微弱反光
        paint.color = Color.argb(26, 255, 255, 255)
        canvas.drawOval(
            RectF(cx - r * 0.34f, cy + r * 0.44f, cx + r * 0.30f, cy + r * 0.66f),
            paint
        )

        // 白色波纹图案（小球适配：两条圆头弧，朝上展开）
        paint.style = Paint.Style.STROKE
        paint.strokeCap = Paint.Cap.ROUND
        val waveAlphas = intArrayOf(255, 150)
        for (i in 0 until 2) {
            paint.strokeWidth = r * (0.16f - i * 0.04f)
            paint.color = Color.argb(waveAlphas[i], 255, 255, 255)
            val rr = r * (0.24f + i * 0.34f)
            val rect = RectF(cx - rr, cy - rr + r * 0.10f, cx + rr, cy + rr + r * 0.10f)
            canvas.drawArc(rect, 248f, 124f, false, paint)
        }
        paint.style = Paint.Style.FILL
    }

    private fun lighten(color: Int, fraction: Float): Int {
        fun ch(c: Int) = (c + (255 - c) * fraction).toInt()
        return Color.argb(255, ch(Color.red(color)), ch(Color.green(color)), ch(Color.blue(color)))
    }

    private fun darken(color: Int, fraction: Float): Int {
        fun ch(c: Int) = (c * (1 - fraction)).toInt()
        return Color.argb(255, ch(Color.red(color)), ch(Color.green(color)), ch(Color.blue(color)))
    }
}
