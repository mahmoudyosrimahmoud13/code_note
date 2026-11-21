package org.code.note.community

import android.content.Intent
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Hands `codenote://` links (inPace's "Practice in CodeNote" button) to the
 * app: the link that started it, and links that arrive while it's open.
 */
class MainActivity : FlutterActivity() {
    private var channel: MethodChannel? = null
    private val pending = mutableListOf<String>()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val c = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "codenote/links")
        c.setMethodCallHandler { call, result ->
            if (call.method == "initialLinks") {
                result.success(ArrayList(pending))
                pending.clear()
            } else {
                result.notImplemented()
            }
        }
        channel = c
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        linkOf(intent)?.let { pending.add(it) }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        val link = linkOf(intent) ?: return
        val c = channel
        if (c != null) c.invokeMethod("link", link) else pending.add(link)
    }

    private fun linkOf(intent: Intent?): String? {
        val data = intent?.data ?: return null
        if (intent.action != Intent.ACTION_VIEW || data.scheme != "codenote") return null
        return data.toString()
    }
}
