package com.marina.marina.data.backup

import com.google.gson.Gson
import com.marina.marina.data.search.SearchEntityKind
import java.util.Locale
import org.junit.Assert.assertEquals
import org.junit.Test

class BackupCompatibilityTest {
    private val gson = Gson()

    @Test
    fun storedFormatsRemainCompatibleWithExistingBackupsAndPreferences() {
        for (format in BackupFormat.entries) {
            assertEquals(format, BackupFormat.fromWireName(format.wireName))
            assertEquals(format, BackupFormat.fromWireName(format.name))
            assertEquals("\"${format.wireName}\"", gson.toJson(format))
            assertEquals(format, gson.fromJson("\"${format.wireName}\"", BackupFormat::class.java))
        }
        assertEquals(BackupFormat.JSON, BackupFormat.fromWireName("json"))
        assertEquals(BackupFormat.SQLITE, BackupFormat.fromWireName("sqlite"))
        assertEquals(BackupFormat.SQLITE, BackupFormat.fromWireName(null))
        assertEquals(BackupFormat.SQLITE, BackupFormat.fromWireName("unsupported"))
    }

    @Test
    fun statusAndSearchKindJsonKeepTheirOriginalNames() {
        val statusNames = listOf(
            "idle", "uploading", "downloading", "restoring", "success", "error",
            "checkingPermissions", "importingFile"
        )
        BackupStatus.entries.zip(statusNames).forEach { (status, original) ->
            assertEquals("\"$original\"", gson.toJson(status))
            assertEquals(status, gson.fromJson("\"$original\"", BackupStatus::class.java))
        }
        val searchNames = listOf(
            "booking", "guestInfo", "payment", "expense", "withdrawal", "debt",
            "employee", "room", "inventoryItem", "blacklist"
        )
        SearchEntityKind.entries.zip(searchNames).forEach { (kind, original) ->
            assertEquals(original, kind.wireName)
            assertEquals("\"$original\"", gson.toJson(kind))
            assertEquals(kind, gson.fromJson("\"$original\"", SearchEntityKind::class.java))
        }
    }

    @Test
    fun fileSizesAreStableOnArabicDevicesAndAtUnitBoundaries() {
        val previous = Locale.getDefault()
        try {
            Locale.setDefault(Locale.forLanguageTag("ar-YE"))
            assertEquals("0 بايت", FileSizeFormatter.formatBytes(0))
            assertEquals("0 بايت", FileSizeFormatter.formatBytes(-1))
            assertEquals("1023.00 بايت", FileSizeFormatter.formatBytes(1023))
            assertEquals("1.00 كيلوبايت", FileSizeFormatter.formatBytes(1024))
            assertEquals("1.5 كيلوبايت", FileSizeFormatter.formatBytes(1536, decimals = 1))
            assertEquals("1.00 ميجابايت", FileSizeFormatter.formatBytes(1L shl 20))
            assertEquals("1.00 جيجابايت", FileSizeFormatter.formatBytes(1L shl 30))
            assertEquals("1.00 تيرابايت", FileSizeFormatter.formatBytes(1L shl 40))
            assertEquals("8388608.00 تيرابايت", FileSizeFormatter.formatBytes(Long.MAX_VALUE))
        } finally {
            Locale.setDefault(previous)
        }
    }
}
