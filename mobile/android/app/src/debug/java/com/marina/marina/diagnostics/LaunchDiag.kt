package com.marina.marina.diagnostics

import android.content.Context
import android.os.Build
import android.util.Log
import com.a.a.BuildConfig
import java.io.File
import java.io.PrintWriter
import java.io.StringWriter
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * Debug-only launch forensics for the "app closes right after MainActivity,
 * with no Java or native stack trace" report.
 *
 * Every stage is written twice:
 *  - logcat, tag [TAG]: `adb logcat -s MarinaDiag:V AndroidRuntime:E`
 *  - `Android/data/com.a.a/files/marina-diag/*.log`, which survives logcat
 *    buffer rotation and can be pulled with a file manager (no root).
 *
 * [startRun] wraps the process default handler and dumps the FULL throwable
 * (message, causes, suppressed, stack) to `crash.log` before delegating, so a
 * fatal exception can no longer disappear without a trace.
 *
 * This source set is `debug` only — none of it ships in the release APK.
 */
object LaunchDiag {

    const val TAG = "MarinaDiag"

    private const val DIR_NAME = "marina-diag"
    private const val STAGES_FILE = "stages.log"
    private const val CRASH_FILE = "crash.log"

    private val clock = SimpleDateFormat("HH:mm:ss.SSS", Locale.US)

    @Volatile private var cachedDir: File? = null
    @Volatile private var started = false

    // ── public API ───────────────────────────────────────────────────────────

    /** Call as the very first statement of a diagnostic Activity's onCreate. */
    fun startRun(context: Context) {
        if (started) return
        started = true
        append(context, STAGES_FILE, header(context))
        val previous = Thread.getDefaultUncaughtExceptionHandler()
        Thread.setDefaultUncaughtExceptionHandler { thread, error ->
            recordFatal(context, error, thread)
            previous?.uncaughtException(thread, error)
        }
    }

    /**
     * Persist a fatal throwable with its full stack to `crash.log`. Used by the
     * handler [startRun] installs; also callable directly so the channel itself
     * is covered by a test.
     */
    fun recordFatal(context: Context, error: Throwable, thread: Thread = Thread.currentThread()) {
        val text = buildString {
            append("\n===== FATAL ${now()} =====\n")
            append("thread : ${thread.name}\n")
            append("pid    : ${android.os.Process.myPid()}\n")
            append(stack(error))
            append("--- stages reached ---\n")
            append(snapshot(context))
            append('\n')
        }
        append(context, CRASH_FILE, text)
        Log.e(TAG, "FATAL EXCEPTION recorded — see $DIR_NAME/$CRASH_FILE", error)
    }

    fun stage(context: Context, name: String) {
        line(context, STAGES_FILE, "STAGE  $name")
    }

    fun note(context: Context, name: String, detail: String) {
        line(context, STAGES_FILE, "NOTE   $name :: $detail")
    }

    fun failure(context: Context, where: String, error: Throwable) {
        Log.e(TAG, "EXCEPTION at $where", error)
        append(context, STAGES_FILE, "${now()}  FAIL   $where\n${stack(error)}")
    }

    /** Everything logged so far — shown on screen so a screenshot is evidence. */
    fun snapshot(context: Context): String {
        return try {
            val file = File(directory(context) ?: return "(no diagnostic dir)", STAGES_FILE)
            if (!file.isFile) "(nothing logged yet)" else file.readText()
        } catch (t: Throwable) {
            "(snapshot failed: ${t.message})"
        }
    }

    // ── internals ────────────────────────────────────────────────────────────

    private fun header(context: Context): String {
        val info = context.applicationInfo
        val nativeLibs = try {
            File(info.nativeLibraryDir).list()?.sorted()?.joinToString(", ") ?: "(none)"
        } catch (t: Throwable) {
            "(unreadable: ${t.message})"
        }
        return buildString {
            append("\n===== run started ${now()} =====\n")
            append("app       : ${context.packageName} v${BuildConfig.VERSION_NAME}+${BuildConfig.VERSION_CODE} debug=${BuildConfig.DEBUG}\n")
            append("device    : ${Build.MANUFACTURER} ${Build.MODEL} / Android ${Build.VERSION.RELEASE} (API ${Build.VERSION.SDK_INT})\n")
            append("application: ${info.className}\n")
            append("apk       : ${info.sourceDir}\n")
            append("dataDir   : ${info.dataDir}\n")
            append("nativeLibs: $nativeLibs\n")
            append("maxHeapMB : ${Runtime.getRuntime().maxMemory() / (1024 * 1024)}\n")
        }
    }

    private fun stack(error: Throwable): String {
        val writer = StringWriter()
        PrintWriter(writer).use { error.printStackTrace(it) }
        return writer.toString()
    }

    private fun line(context: Context, file: String, text: String) {
        Log.i(TAG, text)
        append(context, file, "${now()}  $text\n")
    }

    private fun now(): String = clock.format(Date())

    private fun append(context: Context, file: String, text: String) {
        try {
            val dir = directory(context) ?: return
            File(dir, file).appendText(text)
        } catch (t: Throwable) {
            Log.w(TAG, "could not append to $file", t)
        }
    }

    /** Folder holding `stages.log` / `crash.log` — pull it with a file manager. */
    fun directory(context: Context): File? {
        cachedDir?.let { if (it.isDirectory) return it }
        val base = context.getExternalFilesDir(null) ?: context.filesDir
        val target = File(base, DIR_NAME)
        if (!target.isDirectory && !target.mkdirs()) return null
        cachedDir = target
        return target
    }
}
