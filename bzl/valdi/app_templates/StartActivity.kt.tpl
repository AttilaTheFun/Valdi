package @VALDI_APP_PACKAGE@

import android.os.Bundle
import android.view.MotionEvent
import android.view.View
import android.view.ViewGroup
import android.view.ViewTreeObserver
import com.snap.valdi.support.AppBootstrapper
import com.snap.valdi.support.AppBootstrapActivity

import com.snap.valdi.views.ValdiRootView

class StartActivity : AppBootstrapActivity() {
    // Tap-latency instrumentation (native, content-anchored). tapReceiptNs is
    // stamped when the app receives the tap's ACTION_UP; the OnPreDrawListener
    // stamps the pre-draw pass that first carries the NEW counter text
    // ("re-laid-out and sent for drawing"). The difference SPANS Valdi's async
    // JS round trip (tap -> dispatchOnJsThreadAsync -> onTap -> setState ->
    // view mutation), which the gfxinfo framestats mount-frame anchor misses
    // (blind to JS-thread contention). logcat: [native-tap] latency_us=<n>.
    @Volatile private var tapReceiptNs = 0L
    private var lastCounter: String? = null
    private var downX = 0f
    private var downY = 0f
    private var downAtMs = 0L
    private var traceOpen = false

    override fun createRootView(bootstrapper: AppBootstrapper): ValdiRootView {
        return bootstrapper.setComponentPath("@VALDI_ROOT_COMPONENT_PATH@").createRootView()
    }

    override fun dispatchTouchEvent(ev: MotionEvent): Boolean {
        when (ev.actionMasked) {
            MotionEvent.ACTION_DOWN -> {
                downX = ev.x; downY = ev.y
                downAtMs = android.os.SystemClock.uptimeMillis()
            }
            MotionEvent.ACTION_UP -> {
                // Macrobenchmark's TraceSectionMetric reads "uui-tap": open
                // only for real TAPS (small travel, short hold) - a swipe's
                // ACTION_UP must not dangle a phantom section.
                val slop = android.view.ViewConfiguration.get(this).scaledTouchSlop
                val dx = ev.x - downX; val dy = ev.y - downY
                val held = android.os.SystemClock.uptimeMillis() - downAtMs
                if (dx * dx + dy * dy <= slop.toFloat() * slop && held < 300) {
                    tapReceiptNs = System.nanoTime()
                    android.os.Trace.beginAsyncSection("uui-tap", 0)
                    traceOpen = true
                }
            }
        }
        return super.dispatchTouchEvent(ev)
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val decor = window.decorView
        val content = findViewById<ViewGroup>(android.R.id.content)
        // The mounted counter label's current string ("Tapped N time(s)"), or
        // null if the JS content isn't mounted yet — a literal content check.
        fun counterText(v: View): String? {
            if (v is android.widget.TextView && v.text?.startsWith("Tapped") == true) return v.text.toString()
            if (v is ViewGroup) {
                for (i in 0 until v.childCount) {
                    val r = counterText(v.getChildAt(i))
                    if (r != null) return r
                }
            }
            return null
        }
        // Startup signal [content-frame]: the first draw pass in which the
        // JS-mounted counter label + button exist under the root (the frame
        // that renders the app, not the empty host shell nor a JS render log).
        val startupListener = object : ViewTreeObserver.OnDrawListener {
            private var logged = false
            override fun onDraw() {
                if (logged || counterText(content) == null) return
                logged = true
                android.util.Log.i("UniversalUI", "[content-frame]")
                decor.post { decor.viewTreeObserver.removeOnDrawListener(this) }
            }
        }
        decor.viewTreeObserver.addOnDrawListener(startupListener)
        // Tap signal [native-tap]: the pre-draw pass that first shows a NEW
        // count string. The first sighting (startup "Tapped 0 times") only
        // seeds lastCounter; every later change is tap-driven.
        content.viewTreeObserver.addOnPreDrawListener {
            val cur = counterText(content)
            if (cur != null && cur != lastCounter) {
                val r = tapReceiptNs
                if (lastCounter != null && r != 0L) {
                    android.util.Log.i("UniversalUI", "[native-tap] latency_us=${(System.nanoTime() - r) / 1000}")
                    if (traceOpen) {
                        android.os.Trace.endAsyncSection("uui-tap", 0)
                        traceOpen = false
                    }
                    tapReceiptNs = 0L
                }
                lastCounter = cur
            }
            true
        }
    }
}
