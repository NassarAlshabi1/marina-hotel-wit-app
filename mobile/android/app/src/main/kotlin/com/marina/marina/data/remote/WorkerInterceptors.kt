package com.marina.marina.data.remote

import com.marina.marina.data.auth.LocalAdminAuth
import okhttp3.Interceptor
import okhttp3.MediaType
import okhttp3.Request
import okhttp3.RequestBody
import okhttp3.Response
import okio.Buffer
import java.io.IOException
import java.net.URI

// ═══════════════════════════════════════════════════════════════
//  WorkerInterceptors — طبقة OkHttp فوق Retrofit:
//
//  1. [WorkerAuthInterceptor]: يضيف Authorization: Bearer <JWT> لكل
//     مسارات الـ worker ما عدا الدخول نفسه. التوكن المحلي
//     (local:admin-session) لا يُرسل أبداً — ليس JWT خادمياً.
//
//  2. [WorkerFailoverInterceptor]: تكافؤ endpointPlanner +
//     ResilientHttpClient في Flutter — الطلب يُبنى على نقطة النهاية
//     الفعّالة (نطاق مخصّص إن وُضع، وإلا workers.dev)؛ فشل الشبكة
//     (IOException / 52x من Cloudflare) ينزّل النقطة ويُعيد المحاولة
//     على المرشح التالي (نجاح/فشل يُبلَّغان لـ WorkerEndpoints ليصير
//     sticky عبر الجلسات). أسباب الحجب اليمني تُظهر Connection reset /
//     UnknownHost — كلها IOException فتُلتقط هنا.
// ═══════════════════════════════════════════════════════════════

/**
 * يضيف توكن Bearer لطلبات الـ worker. لا يعترض الدخول (توكن غير موجود
 * أصلاً عندها) ولا يرسل توكن الجلسة المحلية أبداً. يرفق X-Device-Id
 * للتشخيص الخادمي (العمليات تحمل deviceId الخاص بها — العقد الرسمي).
 */
class WorkerAuthInterceptor(
    private val tokenProvider: () -> String?,
    private val deviceIdProvider: () -> String? = { null }
) : Interceptor {

    override fun intercept(chain: Interceptor.Chain): Response {
        val request = chain.request()
        val path = request.url.encodedPath

        // الدخول وفحص الحيوية لا يحتاجان توكن.
        if (path == "/api/auth/login" || path == "/health") {
            return chain.proceed(request)
        }

        val token = tokenProvider()
        // التوكن المحلي ليس JWT خادمياً — إرساله يفشل 401 حتماً.
        if (token.isNullOrEmpty() || LocalAdminAuth.isLocalAdminToken(token)) {
            return chain.proceed(request)
        }

        val builder = request.newBuilder()
            .header("Authorization", "Bearer $token")
        deviceIdProvider()?.takeIf { it.isNotBlank() }?.let { deviceId ->
            builder.header("X-Device-Id", deviceId)
        }
        return chain.proceed(builder.build())
    }
}

/**
 * تبديل نقاط النهاية عند فشل الشبكة — الجسر التنفيذي لـ [WorkerEndpoints].
 * الطلب يُعاد كتابته على النقطة الفعّالة أولاً؛ عند فشل قابلة للتدوير
 * (IOException أو 521/522/530 من Cloudflare) نجرب المرشح التالي.
 */
class WorkerFailoverInterceptor(
    private val endpoints: WorkerEndpoints
) : Interceptor {

    companion object {
        /** حالات Cloudflare التي تعني «الأصل المضيف غير متاح». */
        private val ROTATABLE_STATUS = setOf(521, 522, 530)
    }

    override fun intercept(chain: Interceptor.Chain): Response {
        var request = chain.request()

        // طلب خارج عائلة نقاط الـ worker (api.cloudflare.com مثلًا) — عزل كامل.
        val originalUri = URI(request.url.toString())
        if (!endpoints.isWorkerEndpoint(originalUri)) {
            return chain.proceed(request)
        }

        // Retrofit يبني على المدمج دائماً — نُعيد الكتابة إلى النقطة الفعّالة
        // (النطاق المخصّص مقدَّماً إن وُضع) قبل حساب المرشحين، فتكون أول
        // محاولة على الفعّالة ثم بقية المرشحين (تكافؤ Flutter حيث تُبنى
        // الروابط على CloudflareConfig.workerUrl = WorkerEndpoints.active).
        val activeUri = URI(endpoints.active)

        // نسخة الجسم قابلة لإعادة الإرسال (المحاولات تعيد استهلاكه).
        val bufferedBody: ByteArray? = request.body?.let { body ->
            val buffer = Buffer()
            body.writeTo(buffer)
            buffer.readByteArray()
        }
        val contentType: MediaType? = request.body?.contentType()

        val candidates = endpoints.candidatesFor(activeUri)
        var lastException: IOException? = null
        var lastRotatableResponse: Response? = null

        for (base in candidates) {
            val attempt = rewrite(request, base, bufferedBody, contentType)
            try {
                val response = chain.proceed(attempt)
                if (response.code in ROTATABLE_STATUS) {
                    endpoints.reportFailure(base)
                    // نحتفظ بأول استجابة قابلة للتدوير كي نعيدها لو فشلت كل البدائل.
                    if (lastRotatableResponse == null) {
                        lastRotatableResponse = response
                    } else {
                        response.close()
                    }
                    continue
                }
                if (response.isSuccessful) {
                    endpoints.reportSuccess(base)
                }
                return response
            } catch (e: IOException) {
                // DNS محجوب / Connection reset / timeout — دوّر للمرشح التالي.
                endpoints.reportFailure(base)
                lastException = e
            }
        }

        // كل المرشحين فشلوا: الأفضلية لآخر استجابة خادمية إن وُجدت، وإلا الاستثناء.
        lastRotatableResponse?.let { return it }
        throw lastException ?: IOException("All worker endpoints failed")
    }

    /** يعيد بناء الطلب على قاعدة [base] مع جسم جديد قابل للاستهلاك. */
    private fun rewrite(
        request: Request,
        base: URI,
        body: ByteArray?,
        contentType: MediaType?
    ): Request {
        val url = request.url.newBuilder()
            .scheme(base.scheme)
            .host(base.host)
            .port(if (base.port == -1) if (base.scheme == "https") 443 else 80 else base.port)
            .build()
        val builder = request.newBuilder().url(url)
        if (body != null) {
            builder.method(
                request.method,
                RequestBody.create(contentType, body)
            )
        }
        return builder.build()
    }
}
