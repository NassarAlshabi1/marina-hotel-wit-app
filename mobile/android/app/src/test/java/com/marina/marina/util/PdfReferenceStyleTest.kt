package com.marina.marina.util

import android.app.Application
import android.content.Context
import android.text.TextPaint
import androidx.core.content.res.ResourcesCompat
import androidx.test.core.app.ApplicationProvider
import com.a.a.R
import java.security.MessageDigest
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34], application = Application::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class PdfReferenceStyleTest {
    @Test
    fun bundledFontsAreByteIdenticalToPinnedFlutterPdfReference() {
        val context = ApplicationProvider.getApplicationContext<Context>()
        fun hash(id: Int) = context.resources.openRawResource(id).use { input ->
            MessageDigest.getInstance("SHA-256").digest(input.readBytes()).joinToString("") { "%02x".format(it) }
        }
        assertEquals("c9a039ce48a477243c1eb7d561b13de115cfd651d8a83fa42e2f4d63c2e11b00", hash(R.font.noto_naskh_arabic_regular))
        assertEquals("d328b92b6bb762fd61d6438dddb7b00dd0663115afb292a358101808efe117b2", hash(R.font.noto_naskh_arabic_bold))
        assertNotNull(ResourcesCompat.getFont(context, R.font.noto_naskh_arabic_regular))
        assertNotNull(ResourcesCompat.getFont(context, R.font.noto_naskh_arabic_bold))
        assertEquals(0xFFB46B00.toInt(), PdfExporter.PRIMARY)
    }

    @Test
    fun arabicMixedWithNumbersWrapsInRtlAndRespectsReferenceTwoLineCells() {
        val context = ApplicationProvider.getApplicationContext<Context>()
        val paint = TextPaint().apply {
            textSize = 12f
            typeface = ResourcesCompat.getFont(context, R.font.noto_naskh_arabic_bold)
        }
        val text = "مصروف الموظف 250 بتاريخ 2026/10/05 — وصف طويل ".repeat(10)
        val cell = PdfExporter.layout(text, paint, 85f, maxLines = 2)
        assertEquals(2, cell.lineCount)
        assertEquals(-1, cell.getParagraphDirection(0))
        assertTrue(cell.height > 0)
        assertEquals(85, cell.width)
    }
}
