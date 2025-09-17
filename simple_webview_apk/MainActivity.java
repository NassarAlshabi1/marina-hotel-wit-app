package com.marinahotel.app;

import android.app.Activity;
import android.os.Bundle;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import android.view.Window;
import android.view.WindowManager;

public class MainActivity extends Activity {
    private WebView webView;
    private static final String WEBSITE_URL = "http://10.0.0.57/marina hotel/admin/";
    
    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        
        // إخفاء شريط العنوان
        requestWindowFeature(Window.FEATURE_NO_TITLE);
        getWindow().setFlags(WindowManager.LayoutParams.FLAG_FULLSCREEN,
            WindowManager.LayoutParams.FLAG_FULLSCREEN);
        
        setContentView(R.layout.activity_main);
        
        webView = findViewById(R.id.webview);
        setupWebView();
        
        // تحميل الموقع
        webView.loadUrl(WEBSITE_URL);
    }
    
    private void setupWebView() {
        WebSettings webSettings = webView.getSettings();
        
        // تفعيل JavaScript
        webSettings.setJavaScriptEnabled(true);
        
        // تفعيل DOM Storage
        webSettings.setDomStorageEnabled(true);
        
        // تفعيل Database Storage
        webSettings.setDatabaseEnabled(true);
        
        // تفعيل Application Cache
        webSettings.setAppCacheEnabled(true);
        
        // تحسين للشاشات عالية الدقة
        webSettings.setUseWideViewPort(true);
        webSettings.setLoadWithOverviewMode(true);
        
        // تفعيل Zoom
        webSettings.setSupportZoom(true);
        webSettings.setBuiltInZoomControls(true);
        webSettings.setDisplayZoomControls(false);
        
        // إعدادات إضافية
        webSettings.setAllowFileAccess(true);
        webSettings.setAllowContentAccess(true);
        webSettings.setLoadsImagesAutomatically(true);
        webSettings.setMixedContentMode(WebSettings.MIXED_CONTENT_ALWAYS_ALLOW);
        
        // User Agent مخصص
        webSettings.setUserAgentString(webSettings.getUserAgentString() + " MarinaHotelApp/1.0");
        
        // WebViewClient لمنع فتح المتصفح الخارجي
        webView.setWebViewClient(new WebViewClient() {
            @Override
            public boolean shouldOverrideUrlLoading(WebView view, String url) {
                view.loadUrl(url);
                return true;
            }
            
            @Override
            public void onPageFinished(WebView view, String url) {
                super.onPageFinished(view, url);
                // يمكن إضافة كود JavaScript هنا
                view.evaluateJavascript(
                    "document.body.style.userSelect='none'; " +
                    "document.body.style.webkitUserSelect='none'; " +
                    "document.body.style.webkitTouchCallout='none';", 
                    null
                );
            }
        });
    }
    
    @Override
    public void onBackPressed() {
        if (webView.canGoBack()) {
            webView.goBack();
        } else {
            super.onBackPressed();
        }
    }
    
    @Override
    protected void onResume() {
        super.onResume();
        webView.onResume();
    }
    
    @Override
    protected void onPause() {
        super.onPause();
        webView.onPause();
    }
    
    @Override
    protected void onDestroy() {
        if (webView != null) {
            webView.destroy();
        }
        super.onDestroy();
    }
}