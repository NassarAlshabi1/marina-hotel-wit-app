// إعداد ESLint المسطّح (Flat Config) لمستودع Marina Hotel.
//
// نطاق المستودع الفعلي (حسب `git ls-files "*.js"`):
//   - scripts/appwrite/**  (62 ملفاً) — CommonJS على Node
//   - scripts/**           (9 ملفات)  — CommonJS على Node
//   - assets/js/**, includes/js/**, sw.js (12 ملفاً) — متصفح
//   - functions/**, mobile/functions/** — Cloudflare/Appwrite Functions
//     (fcm-notifier يصرّح بـ "type": "module" في package.json الخاص به)
//
// المبدأ: الكشف عن الأخطاء الحقيقية فقط. هذا كود قائم (legacy)، لذلك القواعد
// الأسلوبية مخفّضة إلى تحذير حتى يبقى التقرير قابلاً للتنفيذ بدل أن يُتجاهل.

const js = require('@eslint/js');
const globals = require('globals');

// ملفات وأدلة لا تُفحص إطلاقاً: مكتبات طرف ثالث، ومخرجات بناء، وتطبيق Flutter.
const sharedIgnores = [
  '**/node_modules/**',
  '**/vendor/**',
  '**/*.min.js',
  '**/dist/**',
  '**/build/**',
  'mobile/**',
  'assets/1js/**',
  'assets/1css/**',
  'tests/**',
  'coverage/**',
];

// قواعد تمثّل أخطاء حقيقية (منطق، أمان، تسريبات) بغضّ النظر عن بيئة التشغيل.
const correctnessRules = {
  // أخطاء منطقية
  'no-cond-assign': ['error', 'except-parens'],
  'no-constant-condition': ['error', { checkLoops: false }],
  'no-dupe-args': 'error',
  'no-dupe-keys': 'error',
  'no-duplicate-case': 'error',
  'no-unreachable': 'error',
  'no-unsafe-negation': 'error',
  'no-fallthrough': 'error',
  'no-self-assign': 'error',
  'no-unused-labels': 'error',
  'use-isnan': 'error',
  'valid-typeof': 'error',

  // أخطاء أمنية
  'no-eval': 'error',
  'no-implied-eval': 'error',
  'no-new-func': 'error',
  'no-script-url': 'error',

  // تسريبات ومتغيرات
  'no-undef': 'error',
  'no-unused-vars': ['warn', { args: 'none', caughtErrors: 'none' }],
  'no-var': 'off', // الكود القائم يعتمد var؛ التحويل الشامل تغيير سلوكي لا فحصي
};

// قواعد مخفّضة إلى تحذير: أنماط موجودة في الكود القائم وسليمة عملياً.
// إبقاؤها تحذيرات (لا أخطاء) هو ما يجعل بوابة `--max-warnings` قابلة للفرض
// في CI بدل أن يُتجاهل التقرير كله.
const styleRules = {
  eqeqeq: ['warn', 'smart'],
  'no-empty': ['warn', { allowEmptyCatch: true }],
  'no-extra-boolean-cast': 'warn',
  'no-useless-escape': 'warn',
  'no-prototype-builtins': 'warn',
  // `let startDate = ''` قبل switch يغطي كل الفروع: التهيئة ليست ميتة عملياً
  'no-useless-assignment': 'warn',
  // `const` داخل case بلا أقواس: يعمل، وإصلاحه تجميلي لا أمني
  'no-case-declarations': 'warn',
  // إرفاق `cause` ممارسة جيدة لكن غيابه ليس عطلاً
  'preserve-caught-error': 'warn',
};

module.exports = [
  { ignores: sharedIgnores },

  js.configs.recommended,

  // ── إعداد ESLint نفسه يعمل على Node/CommonJS ────────────────────────
  {
    files: ['eslint.config.js'],
    languageOptions: {
      ecmaVersion: 2023,
      sourceType: 'commonjs',
      globals: { ...globals.node },
    },
    rules: { ...correctnessRules },
  },

  // ── Node / CommonJS: سكربتات Appwrite والصيانة ──────────────────────
  {
    files: ['scripts/**/*.js'],
    ignores: [
      // هذه الثلاثة تستخدم import/export رغم وجودها تحت scripts/
      'scripts/appwrite/schema/Final_setup_all_collections.js',
      'scripts/messaging/setup_messaging.js',
      'scripts/messaging/test_messaging.js',
    ],
    languageOptions: {
      ecmaVersion: 2023,
      sourceType: 'commonjs',
      globals: { ...globals.node },
    },
    rules: { ...correctnessRules, ...styleRules },
  },

  // ── استثناء: ملفات ESM داخل scripts/ ────────────────────────────────
  {
    files: [
      'scripts/appwrite/schema/Final_setup_all_collections.js',
      'scripts/messaging/setup_messaging.js',
      'scripts/messaging/test_messaging.js',
    ],
    languageOptions: {
      ecmaVersion: 2023,
      sourceType: 'module',
      globals: { ...globals.node },
    },
    rules: { ...correctnessRules, ...styleRules },
  },

  // ── المتصفح: واجهة الإدارة والتقارير وService Worker ────────────────
  {
    files: ['assets/js/**/*.js', 'includes/js/**/*.js', 'sw.js'],
    languageOptions: {
      ecmaVersion: 2023,
      sourceType: 'script',
      globals: {
        ...globals.browser,
        ...globals.jquery,
        // bootstrap يُحمّل عبر <script> من assets/js/vendor
        bootstrap: 'readonly',
        // Chart.js يُحمّل من CDN في admin/reports/comprehensive_reports.php
        // وadmin/finance/cash_reports.php
        Chart: 'readonly',
        // auto_sync.js وenhanced-ui.js يصدّران بنمط UMD (module.exports)
        // حتى يُستخدما من Node ومن المتصفح معاً
        module: 'writable',
        exports: 'writable',
      },
    },
    rules: {
      ...correctnessRules,
      ...styleRules,
      // Service Worker يعتمد نطاقاً عاماً خاصاً
      'no-restricted-globals': 'off',
    },
  },

  // ── Appwrite / Cloudflare Functions (ESM) ───────────────────────────
  {
    files: [
      'functions/**/*.js',
      'mobile/functions/**/*.js',
    ],
    languageOptions: {
      ecmaVersion: 2023,
      sourceType: 'module',
      globals: { ...globals.node },
    },
    rules: { ...correctnessRules, ...styleRules },
  },
];
