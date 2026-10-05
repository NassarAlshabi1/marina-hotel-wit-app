package com.marina.marina.presentation.settings

import android.content.Context
import android.net.Uri
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.google.gson.GsonBuilder
import com.google.gson.JsonParser
import com.marina.marina.data.diagnostics.MaintenanceReport
import com.marina.marina.data.diagnostics.MaintenanceRepository
import com.marina.marina.data.diagnostics.MaintenanceRepairPlan
import com.marina.marina.data.diagnostics.MaintenanceRepairService
import com.marina.marina.data.diagnostics.MaintenanceBackupStore
import com.marina.marina.data.local.dao.QuarantineDetail
import com.marina.marina.domain.session.UserSessionManager
import dagger.hilt.android.lifecycle.HiltViewModel
import dagger.hilt.android.qualifiers.ApplicationContext
import java.security.MessageDigest
import javax.inject.Inject
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

@HiltViewModel
class MaintenanceViewModel @Inject constructor(
    private val repository: MaintenanceRepository,
    private val repairs: MaintenanceRepairService,
    private val backups: MaintenanceBackupStore,
    private val sessions: UserSessionManager,
    @ApplicationContext private val context: Context
) : ViewModel() {
    data class State(
        val loading: Boolean = false, val report: MaintenanceReport? = null, val error: String? = null,
        val draftSearch: String = "", val search: String = "", val entity: String? = null,
        val detail: QuarantineDetail? = null, val plan: MaintenanceRepairPlan? = null,
        val message: String? = null, val quickCheck: String? = null, val historyPage: Long = 0
    )
    private val mutable = MutableStateFlow(State())
    val state = mutable.asStateFlow()
    val repairBusy = repairs.busy

    fun refresh() = perform { read(mutable.value.report?.page ?: 0) }
    fun previousPage() = perform { read(((mutable.value.report?.page ?: 0) - 1).coerceAtLeast(0)) }
    fun nextPage() = perform {
        val report = mutable.value.report
        if (report?.hasNext == true) read(report.page + 1)
    }
    fun historyPage(delta: Long) = perform {
        mutable.value = mutable.value.copy(historyPage = ((mutable.value.report?.historyPage ?: 0) + delta).coerceAtLeast(0))
        read(mutable.value.report?.page ?: 0)
    }
    fun editSearch(value: String) { mutable.value = mutable.value.copy(draftSearch = value.take(120)) }
    fun search() = perform {
        mutable.value = mutable.value.copy(search = mutable.value.draftSearch.trim())
        read(0)
    }
    fun filter(entity: String?) = perform { mutable.value = mutable.value.copy(entity = entity); read(0) }
    fun detail(entity: String, key: String) = perform {
        val result = repository.detail(entity, key)
        mutable.value = mutable.value.copy(detail = result,
            message = if (result == null) "السجل لم يعد موجوداً؛ حدّث التقرير" else null)
    }
    fun dismissDetail() { mutable.value = mutable.value.copy(detail = null) }
    fun dismissPlan() { mutable.value = mutable.value.copy(plan = null) }
    fun preview() = perform { mutable.value = mutable.value.copy(plan = repairs.preview()) }
    fun repair() = perform {
        val plan = mutable.value.plan ?: return@perform
        mutable.value = mutable.value.copy(plan = null)
        val result = repairs.execute(plan.token)
        mutable.value = mutable.value.copy(message = result, quickCheck = null, historyPage = 0)
        read(0)
    }
    fun quickCheck() = perform {
        mutable.value = mutable.value.copy(quickCheck = if (repository.quickCheck())
            "نجح فحص SQLite السريع. لا يثبت صحة الأرصدة أو جميع العلاقات المنطقية."
            else "فشل فحص SQLite السريع؛ احتفظ بنسخة احتياطية واطلب مراجعة متخصصة. لا تنفّذ إصلاح الروابط.")
    }

    fun exportReport(uri: Uri) = perform {
        val report = mutable.value.report ?: return@perform
        // Summary only. No raw payload, guest identity, UUID, search text or backup preimage.
        val summary = mapOf("format" to "maintenance-summary-v1", "capturedAt" to report.capturedAt,
            "schemaVersion" to report.schemaVersion, "counts" to report.counts, "integrity" to report.integrity,
            "salaryCycles" to report.salary, "scope" to "local snapshot, not a full integrity guarantee")
        val bytes = GsonBuilder().setPrettyPrinting().create().toJson(summary).toByteArray(Charsets.UTF_8)
        saveDocument(uri, bytes)
        mutable.value = mutable.value.copy(message = "حُفظ ملخص الصيانة دون حمولات السجلات أو بيانات الضيوف")
    }

    fun exportBackup(token: String, uri: Uri) = perform {
        val run = requireNotNull(mutable.value.report?.history?.firstOrNull { it.runUuid == token && it.status == "completed" })
        val expected = JsonParser.parseString(requireNotNull(run.metadata)).asJsonObject["sha256"].asString
        val bytes = withContext(Dispatchers.IO) {
            val file = backups.file(token)
            check(file.length() in 1..MaintenanceBackupStore.MAX_BACKUP_BYTES.toLong())
            file.readBytes().also { data ->
                val actual = MessageDigest.getInstance("SHA-256").digest(data).joinToString("") { "%02x".format(it) }
                check(actual == expected) { "نسخة الأمان لا تطابق البصمة المسجلة" }
            }
        }
        saveDocument(uri, bytes)
        mutable.value = mutable.value.copy(message = "حُفظت نسخة أمان حقول UUID؛ ليست نسخة كاملة لقاعدة البيانات")
    }

    private suspend fun saveDocument(uri: Uri, bytes: ByteArray) = withContext(Dispatchers.IO) {
        check(sessions.currentUser.value?.isAdmin == true)
        requireNotNull(context.contentResolver.openOutputStream(uri, "wt")).use { it.write(bytes) }
    }
    private suspend fun read(page: Long) {
        val report = repository.read(page, mutable.value.search, mutable.value.entity, mutable.value.historyPage)
        mutable.value = mutable.value.copy(report = report)
    }
    private fun perform(block: suspend () -> Unit) {
        if (mutable.value.loading || repairs.busy.value) return
        mutable.value = mutable.value.copy(loading = true, error = null, message = null)
        viewModelScope.launch {
            try {
                check(sessions.currentUser.value?.isAdmin == true) { "الصيانة متاحة لمدير النظام فقط" }
                block()
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (error: Exception) {
                val ownedMessage = error.message.orEmpty().takeIf { message ->
                    (error is IllegalStateException || error is IllegalArgumentException) &&
                        listOf("انتهت المعاينة", "تغيرت", "توجد مزامنة", "لا توجد روابط", "استبدلت المعاينة",
                            "الصيانة متاحة", "نسخة الأمان").any { message.startsWith(it) }
                }
                mutable.value = mutable.value.copy(error = ownedMessage ?: "تعذر إتمام العملية. حدّث البيانات وراجع سجل نتائج الصيانة.")
            } finally { mutable.value = mutable.value.copy(loading = false) }
        }
    }
}
