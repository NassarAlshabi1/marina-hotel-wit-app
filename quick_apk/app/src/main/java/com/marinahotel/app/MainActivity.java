package com.marinahotel.app;

import android.app.Activity;
import android.os.Bundle;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import android.webkit.WebChromeClient;
import android.view.KeyEvent;
import android.graphics.Bitmap;
import android.view.View;
import android.widget.ProgressBar;

public class MainActivity extends Activity {
    private WebView webView;
    private ProgressBar progressBar;
    private static final String WEBSITE_URL = "http://10.0.0.57/marina hotel/admin/";
    
    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_main);
        
        // العثور على العناصر
        webView = findViewById(R.id.webview);
        progressBar = findViewById(R.id.progressBar);
        
        // إعداد WebView
        setupWebView();
        
        // تحميل الموقع
        webView.loadUrl(WEBSITE_URL);
    }
    
    private void setupWebView() {
        WebSettings webSettings = webView.getSettings();
        
        // الإعدادات الأساسية
        webSettings.setJavaScriptEnabled(true);
        webSettings.setDomStorageEnabled(true);
        webSettings.setDatabaseEnabled(true);
        webSettings.setAppCacheEnabled(true);
        
        // إعدادات العرض
        webSettings.setUseWideViewPort(true);
        webSettings.setLoadWithOverviewMode(true);
        webSettings.setSupportZoom(true);
        webSettings.setBuiltInZoomControls(true);
        webSettings.setDisplayZoomControls(false);
        
        // إعدادات الأمان
        webSettings.setAllowFileAccess(true);
        webSettings.setAllowContentAccess(true);
        webSettings.setMixedContentMode(WebSettings.MIXED_CONTENT_ALWAYS_ALLOW);
        
        // User Agent مخصص
        String userAgent = webSettings.getUserAgentString();
        webSettings.setUserAgentString(userAgent + " MarinaHotelApp/1.0");
        
        // WebViewClient
        webView.setWebViewClient(new WebViewClient() {
            @Override
            public void onPageStarted(WebView view, String url, Bitmap favicon) {
                super.onPageStarted(view, url, favicon);
                progressBar.setVisibility(View.VISIBLE);
            }
            
            @Override
            public void onPageFinished(WebView view, String url) {
                super.onPageFinished(view, url);
                progressBar.setVisibility(View.GONE);
                
                // إضافة CSS للتحسين
                view.evaluateJavascript(
                    "(function() {" +
                    "  var style = document.createElement('style');" +
                    "  style.innerHTML = '" +
                    "    body { font-family: Arial, sans-serif !important; }" +
                    "    * { -webkit-tap-highlight-color: transparent; }" +
                    "    input, textarea { font-size: 16px; }" +
                    "  ';" +
                    "  document.head.appendChild(style);" +
                    "})();", null
                );
            }
            
            @Override
            public boolean shouldOverrideUrlLoading(WebView view, String url) {
                if (url.contains("10.0.0.57") || url.contains("localhost")) {
                    view.loadUrl(url);
                    return true;
                }
                return false;
            }
        });
        
        // WebChromeClient للتقدم
        webView.setWebChromeClient(new WebChromeClient() {
            @Override
            public void onProgressChanged(WebView view, int newProgress) {
                progressBar.setProgress(newProgress);
                if (newProgress == 100) {
                    progressBar.setVisibility(View.GONE);
                }
            }
        });
    }
    
    @Override
    public boolean onKeyDown(int keyCode, KeyEvent event) {
        if (keyCode == KeyEvent.KEYCODE_BACK && webView.canGoBack()) {
            webView.goBack();
            return true;
        }
        return super.onKeyDown(keyCode, event);
    }
    
    @Override
    protected void onPause() {
        super.onPause();
        webView.onPause();
    }
    
    @Override
    protected void onResume() {
        super.onResume();
        webView.onResume();
    }
}