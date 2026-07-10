package @VALDI_APP_PACKAGE@

import android.os.Bundle
import android.view.View
import android.view.ViewGroup
import android.view.ViewTreeObserver
import com.snap.valdi.support.AppBootstrapper
import com.snap.valdi.support.AppBootstrapActivity

import com.snap.valdi.views.ValdiRootView

class StartActivity : AppBootstrapActivity() {
    override fun createRootView(bootstrapper: AppBootstrapper): ValdiRootView {
        return bootstrapper.setComponentPath("@VALDI_ROOT_COMPONENT_PATH@").createRootView()
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Benchmark instrumentation: the uniform [content-frame] startup
        // signal — the first UI-toolkit draw pass in which the JS-mounted
        // content views exist under the root, i.e. the frame that actually
        // renders the app, not the empty host shell and not a JS-side render
        // log. Mirrors the other benchmark cells' ContentFrame helper.
        val decor = window.decorView
        val content = findViewById<ViewGroup>(android.R.id.content)
        fun descendants(v: View, budget: Int): Int {
            var count = 1
            if (v is ViewGroup) {
                for (i in 0 until v.childCount) {
                    count += descendants(v.getChildAt(i), budget - count)
                    if (count >= budget) return count
                }
            }
            return count
        }
        val listener = object : ViewTreeObserver.OnDrawListener {
            private var logged = false
            override fun onDraw() {
                // content -> ValdiRootView -> view(root) -> label + button.
                if (logged || descendants(content, 5) < 5) return
                logged = true
                android.util.Log.i("UniversalUI", "[content-frame]")
                decor.post { decor.viewTreeObserver.removeOnDrawListener(this) }
            }
        }
        decor.viewTreeObserver.addOnDrawListener(listener)
    }
}
