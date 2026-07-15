package io.neurodienst.app

import android.media.AudioManager
import android.media.ToneGenerator
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "neuro_app/feedback_sound"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            channelName
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "playLogin" -> {
                    playToneSequence(
                        intArrayOf(
                            ToneGenerator.TONE_CDMA_ALERT_CALL_GUARD,
                            ToneGenerator.TONE_CDMA_CONFIRM
                        ),
                        intArrayOf(140, 180),
                        88
                    )
                    result.success(null)
                }
                "playRoleSelected" -> {
                    playToneSequence(
                        intArrayOf(
                            ToneGenerator.TONE_DTMF_6,
                            ToneGenerator.TONE_DTMF_9
                        ),
                        intArrayOf(90, 110),
                        58
                    )
                    result.success(null)
                }
                "playSuccess" -> {
                    playToneSequence(
                        intArrayOf(ToneGenerator.TONE_CDMA_CONFIRM),
                        intArrayOf(150),
                        78
                    )
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun playToneSequence(tones: IntArray, durations: IntArray, volume: Int) {
        val toneGenerator = ToneGenerator(AudioManager.STREAM_MUSIC, volume)
        var delay = 0L

        tones.forEachIndexed { index, tone ->
            val duration = durations.getOrElse(index) { 100 }

            window.decorView.postDelayed({
                toneGenerator.startTone(tone, duration)
            }, delay)

            delay += duration + 45L
        }

        window.decorView.postDelayed({
            toneGenerator.release()
        }, delay + 80L)
    }
}
