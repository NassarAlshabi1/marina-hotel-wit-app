#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
تدقيق ربط الموظفين بالمصروفات وسحوبات الرواتب — النسخة المُصلَّحة
====================================================================
يقرأ 3 ملفات CSV مُصدَّرة من Appwrite (Expenses / Salary_Withdrawals / Employees)
وينتج تقرير Excel شامل بالتدقيق والاستحقاقات والسجلات اليتيمة.
🔴 قراءة فقط: لا اتصال بالسحابة، ولا أي عملية كتابة على أي مصدر بيانات.

الإصلاحات مُوثَّقة بمراجعها من كود التطبيق نفسه (لا تخمين):
  * employee_link_consistency_service.dart — «employeeUuid يفوز دائماً»،
    «لا يُحسم بالتخمين»، إنقاذ السحوبات عبر مصروفها فقط.
  * salary_withdrawals_repository.dart (هجرة 68) — الرابط الحاكم:
    سحبة.expenseUuid ↔ مصروف.localUuid باتجاهين، ثمexpenseId الرقمي،
    ثم reason=exp_N، ثم تبنّي مرآة يتيمة.
  * backfill_withdrawal_expense_uuid.py — حراس المطابقة:
    (نفس الموظف + نفس المبلغ ±0.005 + نفس اليوم) + فرادة المرشح.
  * audit_full_mirror.py — منهجية «deleted-aware» (وعي الحذف الناعم).
  * payload_mapper.dart — أسماء أعمدة السحابة الفعلية:
    الموظفون: salary (ولا يوجد basicSalary على السحابة)؛
    السحوبات: withdrawDate + اسم تراثي date + action/note؛
    المصروفات: relatedId/employeeUuid/withdrawalUuid ولا يوجد id رقمي.
  * salary_expense_classifier.dart — أنواع الرواتب النقدية والخصوم.

تشخيص أعطال النسخة الأصلية (كل عطل مُثبت بمرجعه):
  F01 كاتب Excel متداخل (فتح الملف مرتين داخل with واحدة) → فقدان
      أوراق اليتامى أو انهيار عند غياب ملف قديم. الإصلاح: كاتب واحد.
  F02 اختيار عمود basicSalary من الموظفين → KeyError (السحابة ترسل salary).
  F03 عمود date للسحوبات اسم تراثي؛ الأساس withdrawDate → يُحلّان معاً.
  F04 تمييز سجلات المزامنة للموظفين كان على localUuid (لا يطابق أبداً؛
      بادئات backup_/mig33_/... تقبع في عمود معرّف المستند id).
  F05 مفتاح «سحبة.localUuid ∈ مصروف.id» ليس رابط التطبيق؛ الصحيح
      expenseUuid ↔ localUuid (+withdrawalUuid عكسياً) — F05 أخطر عطل
      منطقي لأنه يُظهر أغلب السحوبات «بلا مصروف» زوراً.
  F06 لا وعي للحذف الناعم deletedAt رغم أن كل تدقيقات التطبيق deleted-aware.
  F07 الموظفون بلا إزالة تكرار (تكرارات السحابة موثقة في cleanup_duplicate_
      employees.js) → تضخيم ديكارتي في دمج الاستحقاقات.
  F08 dedupe_latest يُسقط صفوف localUuid الفارغ كلها في صف واحد (NaN==NaN).
  F09 تحويل epoch كان مُبهماً (ثوانٍ/ملّي بلا تمييز) ونتائجه لم تكن
      مستخدمة في أي حساب أصلاً — حُذف؛ ومطابقة الأيام حرفية (حرّاس هجرة 68).
  F10 «سحوبات بلا مصروف» كانت تُحسب من كل الصفوف بما فيها نسخ المزامنة.
  F11 عدم توحيد حالة UUID (case/فراغات) → روابط ضائعة.
  F12 عمود فحص expenseId كان يُصنّف الرقمي «مكسوراً» بينما الدلالة
      الصحيحة: expenseId رقمي = مرجع جهاز المصدر (غير محمول)؛ الحاكم
      هو expenseUuid — يُفحص التنسيق + الحل + التناسق مع reason=exp_N.
  F13 لا تصنيف متفق عليه (سليم/قابل للإصلاح/غامض/يتيم/تعارض).

الاستخدام:
  python3 audit_csv_linkage.py [expenses.csv withdrawals.csv employees.csv output.xlsx]
  الافتراضي: البحث عن أسماء الملفات في المجلد الحالي ثم في
  /home/z/my-project/upload/ — والخرج audit_report.xlsx في المجلد الحالي.
"""

import os
import re
import sys

import numpy as np
import pandas as pd

# ============================================================
# 1) إعدادات عامة
# ============================================================
DEFAULT_EXPENSES = "Expenses_2026-10-04T23-15-42.csv"
DEFAULT_WITHDRAWALS = "Salary_Withdrawals_2026-10-04T23-15-10.csv"
DEFAULT_EMPLOYEES = "Employees_2026-10-04T23-16-52.csv"
DEFAULT_OUTPUT = "audit_report.xlsx"
UPLOAD_DIR = "/home/z/my-project/upload"

# بادئات معرّفات مستندات المزامنة/النسخ الاحتياطي (تظهر في عمود id = $id)
SYNC_PATTERNS = re.compile(
    r"^(backup_|backfill|mig33_|salary_withdrawals:|expenses:"
    r"|employees:update:|employees:create:)",
    re.IGNORECASE,
)

# عرف داخلي موثّق (هجرة 33 والتقارير): reason = exp_NNN حيث NNN معرّف
# المصروف الرقمي على جهاز المصدر.
REASON_RE = re.compile(r"^exp_(\d+)$")

# حرّاس المطابقة (من backfill_withdrawal_expense_uuid.py):
AMOUNT_TOLERANCE = 0.005

# عتبات الحالات الشاذة (من السكربت الأصلي — نوايا صاحب البيانات):
BIG_WITHDRAWAL = 20000
BIG_EXPENSE = 100000

# أنواع المصروفات المرتبطة بالرواتب (salary_expense_classifier.dart):
SALARY_CASH_OUT_KEYWORDS = ("رواتب", "سحب راتب", "سحب من الراتب", "سلفة")
SALARY_DEDUCTION_KEYWORDS = ("خصم من الراتب", "خصم راتب", "خصم", "غياب")

# تصنيف التدقيق المتفق عليه:
CLS_OK = "سليم"
CLS_REPAIRABLE = "قابل للإصلاح"
CLS_AMBIGUOUS = "غامض"
CLS_ORPHAN = "يتيم"
CLS_CONFLICT = "تعارض"
CLASS_ORDER = [CLS_OK, CLS_REPAIRABLE, CLS_AMBIGUOUS, CLS_ORPHAN, CLS_CONFLICT]

# ألوان التنسيق (لمسة احترافية هادئة — رأس كحلي + صفوف متناوبة):
STYLE_HEADER_FILL = "1B2A4A"
STYLE_HEADER_TEXT = "FFFFFF"
STYLE_ZEBRA = "F7F7F5"
ZEBRA_MAX_ROWS = 800  # فوق ذلك نكتفي بالرأس والتنسيقات خوفاً من حجم الملف

UUID_RE = re.compile(
    r"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$",
    re.IGNORECASE,
)


# ============================================================
# 2) دوال قراءة وتنظيف آمنة
# ============================================================
def find_file(name: str) -> str:
    """البحث عن الملف في المجلد الحالي ثم في مجلد الرفع."""
    if os.path.isabs(name) and os.path.isfile(name):
        return name
    for base in (os.getcwd(), UPLOAD_DIR):
        cand = os.path.join(base, name)
        if os.path.isfile(cand):
            return cand
    return name  # يُترك للفشل مع رسالة واضحة عند التحميل


def read_csv_safe(path: str) -> pd.DataFrame:
    """قراءة CSV مع إزالة صفوف الرأس المكررة والقيم الفارغة."""
    if not os.path.isfile(path):
        searched = [os.path.dirname(path) or ".", UPLOAD_DIR]
        sys.exit(
            f"❌ الملف غير موجود: {path}\n"
            f"   تم البحث في: {searched}\n"
            f"   مرّر المسار الكامل كوسيطة: "
            f"audit_csv_linkage.py <expenses.csv> <withdrawals.csv> "
            f"<employees.csv> [output.xlsx]"
        )
    df = pd.read_csv(path, low_memory=False, encoding="utf-8-sig", dtype=str)
    if df.empty:
        sys.exit(f"❌ الملف فارغ: {path}")

    # حذف الصفوف التي يكون فيها العمود الأول = اسم العمود (رأس مكرر)
    first_col = df.columns[0]
    df = df[df[first_col].astype(str) != first_col]

    # تنظيف أسماء الأعمدة (BOM + فراغات)
    df.columns = [str(c).strip().lstrip("\ufeff") for c in df.columns]
    # إزالة الأعمدة المكررة (نفس الاسم يظهر مرتين)
    df = df.loc[:, ~pd.Index(df.columns).duplicated()]
    # إزالة الصفوف الفارغة تماماً
    df = df.dropna(how="all").reset_index(drop=True)
    print(f"   📄 {os.path.basename(path)}: {len(df)} صف، "
          f"{len(df.columns)} عمود")
    return df


def col(df: pd.DataFrame, *candidates: str):
    """أول عمود موجود من المرشحات (تصدير Appwrite يستعمل أسماء متعددة
    للحقول التراثية: withdrawDate/withdrawalDate/date ... إلخ)."""
    for name in candidates:
        if name in df.columns:
            return name
    return None


def require_col(df: pd.DataFrame, purpose: str, *candidates: str) -> str:
    """عمود إلزامي مع رسالة تشخيصية دقيقة بدل KeyError غامض (إصلاح F02)."""
    name = col(df, *candidates)
    if name is None:
        sys.exit(
            f"❌ عمود إلزامي مفقود ({purpose}): بحثت عن أي من {list(candidates)}\n"
            f"   الأعمدة المتوفرة: {list(df.columns)}\n"
            f"   راجع تصدير Appwrite — راجع payload_mapper.dart لأسماء الحقول."
        )
    return name


def norm_uuid(v) -> str:
    """توحيد UUID للمطابقة (strip + lower) — إصلاح F11.
    لا يغيّر القيم المخزّنة، يُستخدم للمفاتيح فقط."""
    if v is None or (isinstance(v, float) and np.isnan(v)):
        return ""
    s = str(v).strip().lower()
    return s if s and s not in ("nan", "none") else ""


def sstr(v) -> str:
    """قيمة نصية آمنة: NaN/None/الفراغات الخفية → '' (بدل str(nan)='nan')."""
    if v is None:
        return ""
    if isinstance(v, float) and np.isnan(v):
        return ""
    s = str(v).strip()
    return "" if s.lower() in ("nan", "none", "null") else s


def num(v):
    """تحويل رقمي آمن (لا يُرجع 0 زوراً عند الفقد — يُرجع None)."""
    if v is None:
        return None
    if isinstance(v, bool):
        return None
    try:
        f = float(str(v).strip())
        return f if f == f else None  # يستبعد NaN
    except (ValueError, TypeError):
        return None


def truthy_deleted(v) -> bool:
    """deletedAt صالح؟ (epoch>0 أو أي قيمة نصية غير فارغة) — وعي الحذف F06."""
    if v is None:
        return False
    if isinstance(v, float) and np.isnan(v):
        return False
    n = num(v)
    if n is not None:
        return n > 0
    return str(v).strip() != ""


def dedupe_latest(df: pd.DataFrame, key: str) -> pd.DataFrame:
    """أحدث إصدار لكل مفتاح غير فارغ (إصلاحات F07/F08/F09):
    - صفوف المفتاح الفارغ تُحفظ كلها ولا تُدمج (NaN!=NaN منطقياً هنا)؛
    - الترتيب: version ثم lastModified ثم updatedAt (سياسة LWW للتطبيق)؛
    - يحافظ على ترتيب الملف الأصلي في الخرج."""
    if df.empty:
        return df.copy()
    out = df.copy()
    key_empty = out[key].isna() | (out[key].astype(str).str.strip() == "")
    rank = pd.Series(0.0, index=out.index)
    for c, w in (("version", 1e12), ("lastModified", 1.0), ("updatedAt", 1.0)):
        if c in out.columns:
            vals = pd.to_numeric(out[c], errors="coerce").fillna(0) * w
            rank = rank + vals
            if c == "lastModified":
                break  # lastModified أقوى من updatedAt عند وجوده
    out["__rank"] = rank
    grouped = out[~key_empty].groupby(key, sort=False)["__rank"]
    keep_idx = set(grouped.idxmax().tolist())  # التعادل = أول ظهور (ترتيب الملف)
    keep_idx |= set(out.index[key_empty])
    keep_idx = sorted(keep_idx)
    res = out.loc[keep_idx].drop(columns="__rank")
    dropped = len(out) - len(res)
    if dropped:
        print(f"      ↳ إزالة تكرار {key}: -{dropped} صف قديم")
    return res


def is_uuid(s: str) -> bool:
    return bool(UUID_RE.match(s)) if s else False


def salary_cash_out(t: str) -> bool:
    t = (t or "").strip()
    return bool(t) and any(k in t for k in SALARY_CASH_OUT_KEYWORDS)


def salary_deduction(t: str) -> bool:
    t = (t or "").strip()
    return bool(t) and any(k in t for k in SALARY_DEDUCTION_KEYWORDS)


def salary_related(t: str) -> bool:
    return salary_cash_out(t) or salary_deduction(t)


# ============================================================
# 3) التحميل والتشخيص الأولي
# ============================================================
def load_all(exp_path, wd_path, emp_path):
    print("📥 تحميل الملفات...")
    exp = read_csv_safe(exp_path)
    wd = read_csv_safe(wd_path)
    emp = read_csv_safe(emp_path)

    # ═══ أسماء الأعمدة الحرجة (تُحلّ بمرونة مع تشخيص دقيق) ═══
    cols = {}
    for tag, df, purpose, cands in [
        ("exp_id", exp, "معرّف مستند المصروف (id/$id)", ("id", "$id")),
        ("exp_uuid", exp, "localUuid للمصروف", ("localUuid",)),
        ("exp_amount", exp, "مبلغ المصروف", ("amount",)),
        ("exp_type", exp, "نوع المصروف", ("expenseType", "type", "category")),
        ("exp_date", exp, "تاريخ المصروف", ("date", "expenseDate")),
        ("exp_emp_uuid", exp, "employeeUuid للمصروف", ("employeeUuid",)),
        ("exp_wd_uuid", exp, "withdrawalUuid للمصروف", ("withdrawalUuid",)),
        ("wd_id", wd, "معرّف مستند السحبة (id/$id)", ("id", "$id")),
        ("wd_uuid", wd, "localUuid للسحبة", ("localUuid",)),
        ("wd_amount", wd, "مبلغ السحبة", ("amount",)),
        ("wd_date", wd, "تاريخ السحبة (withdrawDate هو الأساس؛ "
                        "date اسم تراثي — payload_mapper.dart)",
         ("withdrawDate", "withdrawalDate", "date")),
        ("wd_emp_uuid", wd, "employeeUuid للسحبة", ("employeeUuid",)),
        ("wd_type", wd, "نوع السحبة", ("withdrawalType", "action")),
        ("wd_exp_uuid", wd, "expenseUuid للسحبة", ("expenseUuid",)),
        ("wd_exp_id", wd, "expenseId الرقمي التراثي", ("expenseId",)),
        ("wd_reason", wd, "reason للسحبة", ("reason",)),
        ("emp_id", emp, "معرّف مستند الموظف (id/$id)", ("id", "$id")),
        ("emp_uuid", emp, "localUuid للموظف", ("localUuid",)),
        ("emp_name", emp, "اسم الموظف", ("name",)),
        ("emp_salary", emp, "راتب الموظف (السحابة ترسل salary من "
                            "basicSalary — payload_mapper.dart:370)",
         ("salary", "basicSalary")),
    ]:
        cols[tag] = require_col(df, purpose, *cands)

    # أعمدة اختيارية شائعة
    opt = {
        "emp_status": col(emp, "status"),
        "emp_position": col(emp, "position"),
        "emp_server_id": col(emp, "serverId"),
        "emp_hire": col(emp, "hireDate"),
        "emp_term": col(emp, "terminationDate"),
        "emp_basic": col(emp, "basicSalary"),
        "exp_related": col(exp, "relatedId"),
        "exp_desc": col(exp, "description"),
        "exp_hotel_day": col(exp, "hotelDayKey"),
        "wd_desc": col(wd, "description", "note"),
        "wd_hotel_day": col(wd, "hotelDayKey"),
        "wd_emp_id_num": col(wd, "employeeId"),
        "version": col(wd, "version"),
    }
    cols.update(opt)
    return exp, wd, emp, cols


def prepare_frame(df, id_col, uuid_col):
    """أعمدة مشتقة: مفتاح UUID الموحّد، الحذف الناعم، سجل المزامنة، الرقميات."""
    out = df.copy()
    out["uuid_key"] = out[uuid_col].map(norm_uuid)
    out["id_str"] = out[id_col].astype(str).str.strip()
    # إصلاح F04: التمييز على معرّف المستند (البادئات تقبع هناك) وليس localUuid
    out["is_sync_record"] = out["id_str"].map(
        lambda s: bool(SYNC_PATTERNS.match(s)))
    out["is_deleted"] = False  # تُضبط بعد معرفة عمود deletedAt
    if "deletedAt" in out.columns:
        out["is_deleted"] = out["deletedAt"].map(truthy_deleted)
    return out


# ============================================================
# 4) محرك التدقيق: حلّ الموظف + تدقيق المرآة + التصنيف
# ============================================================
def build_employee_universe(emp, cols):
    """كون الموظفين: إزالة التكرار (F07) + فصل المحذوف/المزامنة."""
    emp_p = prepare_frame(emp, cols["emp_id"], cols["emp_uuid"])
    emp_d = dedupe_latest(emp_p, "uuid_key")

    emp_live = emp_d[
        ~emp_d["is_deleted"] & ~emp_d["is_sync_record"] & (emp_d["uuid_key"] != "")
    ].copy()

    # خرائط الحل: uuid → صف، serverId → صف (إصلاح دلالة الحل الرقمي:
    # employeeId الرقمي في السحوبات = id جهاز المصدر، ويُحلّ ضد serverId
    # للموظفين — نفس نهج backfill_withdrawal_expense_uuid.py)
    by_uuid = {r["uuid_key"]: r for _, r in emp_live.iterrows()}
    by_server = {}
    if cols.get("emp_server_id"):
        for _, r in emp_live.iterrows():
            sid = num(r[cols["emp_server_id"]])
            if sid is not None:
                by_server.setdefault(int(sid), r)  # الأول عند التكرار

    deleted_uuids = set(emp_d.loc[emp_d["is_deleted"], "uuid_key"]) - {""}
    sync_uuids = set(emp_d.loc[emp_d["is_sync_record"], "uuid_key"]) - {""}

    stats = {
        "raw": len(emp),
        "dedup": len(emp_d),
        "live": len(emp_live),
        "deleted": int(emp_d["is_deleted"].sum()),
        "sync": int(emp_d["is_sync_record"].sum()),
        "dup_localuuid": int((emp_p.groupby("uuid_key").size() > 1).sum()),
    }
    return emp_p, emp_d, emp_live, by_uuid, by_server, deleted_uuids, sync_uuids, stats


def resolve_employee(row_uuid_key, row_emp_num, by_uuid, by_server):
    """حلّ موظف سجلٍ ما. يعيد (class, reason, uuid, name, server_id_row).
    سياسة «UUID يفوز» + «لا تخمين» (employee_link_consistency_service.dart).
    """
    if row_uuid_key and row_uuid_key in by_uuid:
        r = by_uuid[row_uuid_key]
        name = sstr(r["name"]) if "name" in r.index else ""
        return CLS_OK, "employeeUuid يحلّ لموظف قائم", row_uuid_key, name
    if row_uuid_key:
        # UUID موجود لكن لا موظف قائم يحمله → يتيم (لا تخمين مطلقاً)
        return CLS_ORPHAN, "employeeUuid لا يشير لأي موظف في التصدير", \
            row_uuid_key, ""
    # لا UUID: الحل الرقمي ضد serverId فقط (دليل موثق)، وإلا يتيم
    sid = num(row_emp_num) if row_emp_num is not None else None
    if sid is not None and int(sid) in by_server:
        r = by_server[int(sid)]
        name = sstr(r["name"]) if "name" in r.index else ""
        return CLS_REPAIRABLE, "employeeUuid فارغ ويُحلّ رقمياً عبر serverId " \
                               "(قابل لإعادة البناء)", r["uuid_key"], name
    return CLS_ORPHAN, "بلا employeeUuid ولا حلّ رقمي (serverId)", "", ""


def audit_withdrawal(row, cols, ctx):
    """تدقيق سحبة واحدة: الموظف + المرآة → (تصنيف نهائي، سبب، تفاصيل)."""
    notes = []
    emp_cls, emp_reason, emp_key, emp_name = resolve_employee(
        norm_uuid(row[cols["wd_emp_uuid"]]),
        row[cols["wd_emp_id_num"]] if cols.get("wd_emp_id_num") else None,
        ctx["by_uuid"], ctx["by_server"],
    )

    # ── حلّ الموظف المحذوف ناعماً (معلوماتي — audit_full_mirror.py) ──
    if emp_key and emp_key in ctx["deleted_uuids"]:
        notes.append("الموظف محذوف ناعماً (deletedAt)")

    # ── المرآة: الرابط الحاكم (هجرة 68) ──
    exp_uuid = norm_uuid(row[cols["wd_exp_uuid"]])
    amount = num(row[cols["wd_amount"]])
    wd_date = sstr(row[cols["wd_date"]])
    wd_hdk = sstr(row[cols["wd_hotel_day"]]) if cols.get("wd_hotel_day") else ""

    mir_cls, mir_reason = CLS_OK, "بلا رابط مرآة — غير مطلوب"
    matched_exp, candidates = None, []

    if exp_uuid:
        exp = ctx["exp_by_uuid"].get(exp_uuid)
        if exp is None:
            exp = ctx["exp_by_id"].get(exp_uuid)
        if exp is None:
            mir_cls, mir_reason = CLS_ORPHAN, \
                "expenseUuid يشير لمصروف غير موجود في التصدير (رابط مكسور)"
        else:
            matched_exp = exp
            if exp["is_deleted"]:
                mir_cls, mir_reason = CLS_ORPHAN, "المرآة محذوفة ناعماً (deletedAt)"
            else:
                # تناسق الموظف بين السحبة ومصروفها (تعارض هويّتين حاكمتين)
                exp_emp = norm_uuid(exp[cols["exp_emp_uuid"]]) \
                    if cols.get("exp_emp_uuid") else ""
                if emp_key and exp_emp and exp_emp != emp_key:
                    mir_cls, mir_reason = CLS_CONFLICT, \
                        "تعارض الموظف: السحبة تحمل موظفاً والمصروف موظفاً آخر"
                elif amount is not None:
                    exp_amount = num(exp[cols["exp_amount"]])
                    if exp_amount is not None and \
                            abs(exp_amount - amount) >= AMOUNT_TOLERANCE:
                        mir_cls, mir_reason = CLS_CONFLICT, \
                            f"اختلاف مبلغ المرآة (سحبة {amount:g} / مصروف {exp_amount:g})"
                    else:
                        back = norm_uuid(exp[cols["exp_wd_uuid"]])
                        if back == row["uuid_key"]:
                            mir_cls, mir_reason = CLS_OK, "مرآة متبادلة سليمة"
                        elif back == "":
                            mir_cls, mir_reason = CLS_REPAIRABLE, \
                                "الرابط العكسي withdrawalUuid ناقص بالمصروف"
                        else:
                            mir_cls, mir_reason = CLS_CONFLICT, \
                                "المصروف يرتبط بسحبة أخرى (withdrawalUuid)"
                else:
                    mir_cls, mir_reason = CLS_AMBIGUOUS, \
                        "مبلغ السحبة غير رقمي — غير قابل للتدقيق الحسابي"
    else:
        # بلا expenseUuid: البحث عن مرشح بالحرّاس الموثقة (backfill...)
        # (نفس الموظف + المبلغ ±0.005 + نفس اليوم) + فرادة المرشح،
        # مع استبعاد المرايا المطالَب بها من سحبات أخرى (نهج «تبنّي يتيمة»).
        if emp_key:
            pool = ctx["exp_candidates"]  # مرايا حية غير مُطالَب بها
            candidates = [
                e for e in pool
                if e["emp_key"] == emp_key
                and amount is not None and e["amount"] is not None
                and abs(e["amount"] - amount) < AMOUNT_TOLERANCE
                and (e["date_str"] == wd_date
                     or (wd_hdk != "" and e["hdk_str"] == wd_hdk))
            ]
            if len(candidates) == 1:
                matched_exp = candidates[0]
                mir_cls, mir_reason = CLS_REPAIRABLE, \
                    "رابط قابل لإعادة البناء (موظف+مبلغ+يوم — حرّاس هجرة 68)"
            elif len(candidates) > 1:
                mir_cls, mir_reason = CLS_AMBIGUOUS, \
                    f"تعدد مرشحين ({len(candidates)}) — خطر ربط خاطئ"
            else:
                mir_cls, mir_reason = CLS_ORPHAN, "بلا مصروف مقابل"
        else:
            mir_cls, mir_reason = CLS_ORPHAN, \
                "بلا رابط مرآة والموظف غير قابل للحل — لا يمكن البحث عن مرشح"

    # تناسق reason=exp_N مع expenseId الرقمي (عرف داخلي موثق)
    reason = sstr(row[cols["wd_reason"]]) if cols.get("wd_reason") else ""
    m = REASON_RE.match(reason)
    raw_eid = num(row[cols["wd_exp_id"]]) if cols.get("wd_exp_id") else None
    reason_note = ""
    if m and raw_eid is not None and int(m.group(1)) != int(raw_eid):
        reason_note = f"reason={reason} يتعارض مع expenseId={int(raw_eid)}"
        mir_cls = CLS_CONFLICT
        mir_reason += "؛ " + reason_note

    # التصنيف النهائي = أسوأ الطرفين (الموظف، المرآة)
    worst = max([emp_cls, mir_cls], key=lambda c: CLASS_ORDER.index(c))
    full_reason = " | ".join(
        x for x in (emp_reason, mir_reason) if x)
    return {
        "class": worst,
        "reason": full_reason,
        "emp_cls": emp_cls,
        "emp_reason": emp_reason,
        "mir_cls": mir_cls,
        "mir_reason": mir_reason,
        "emp_key": emp_key,
        "emp_name": emp_name,
        "matched_exp_id": matched_exp["id_str"] if matched_exp is not None else "",
        "matched_exp_uuid": matched_exp["uuid_key"] if matched_exp is not None else "",
        "candidates": len(candidates),
        "notes": "؛ ".join(notes),
    }


# ============================================================
# 5) تدقيق المصروفات (الجهة المقابلة للمرآة)
# ============================================================
def audit_expense(row, cols, ctx):
    """تدقيق مصروف: ربط الموظف + مرآة السحبة (لأنواع الرواتب)."""
    etype = sstr(row[cols["exp_type"]])
    is_sal = salary_related(etype)

    # ── ربط الموظف: employeeUuid يفوز، ثم relatedId ضد serverId ──
    emp_uuid = norm_uuid(row[cols["exp_emp_uuid"]])
    related = num(row[cols["exp_related"]]) if cols.get("exp_related") else None
    if emp_uuid and emp_uuid in ctx["by_uuid"]:
        emp_cls, emp_reason, emp_key = CLS_OK, "employeeUuid يحلّ لموظف قائم", emp_uuid
    elif emp_uuid:
        emp_cls, emp_reason, emp_key = CLS_ORPHAN, \
            "employeeUuid لا يشير لأي موظف في التصدير", emp_uuid
    elif related is not None and int(related) in ctx["by_server"]:
        emp_cls, emp_reason, emp_key = CLS_REPAIRABLE, \
            "employeeUuid فارغ ويُحلّ عبر relatedId↔serverId", \
            ctx["by_server"][int(related)]["uuid_key"]
    elif not is_sal:
        # مصروف عام بلا موظف = حالة سليمة (نوايا السكربت الأصلي)
        emp_cls, emp_reason, emp_key = CLS_OK, "مصروف عام (بلا موظف) — سليم", ""
    else:
        emp_cls, emp_reason, emp_key = CLS_ORPHAN, \
            "مصروف رواتب بلا رابط موظف قابل للحل", ""
    if emp_key and emp_key in ctx["deleted_uuids"]:
        emp_reason += "؛ الموظف محذوف ناعماً"

    # ── المرآة العكسية: withdrawalUuid (لأنواع الرواتب حصراً) ──
    back = norm_uuid(row[cols["exp_wd_uuid"]])
    mir_cls, mir_reason = CLS_OK, "لا تتطلب مرآة (مصروف عام)"
    matched_wd = ""
    if back:
        w = ctx["wd_by_uuid"].get(back)
        if w is None:
            w = ctx["wd_by_id"].get(back)
        if w is None:
            mir_cls, mir_reason = CLS_ORPHAN, \
                "withdrawalUuid يشير لسحبة غير موجودة في التصدير"
        elif w["is_deleted"]:
            mir_cls, mir_reason = CLS_ORPHAN, "السحبة المقابلة محذوفة ناعماً"
        else:
            matched_wd = w["uuid_key"]
            fwd = norm_uuid(w[cols["wd_exp_uuid"]])
            if fwd == row["uuid_key"]:
                mir_cls, mir_reason = CLS_OK, "مرآة متبادلة سليمة"
            elif fwd == "":
                mir_cls, mir_reason = CLS_REPAIRABLE, \
                    "expenseUuid ناقص بالسحبة (الرابط العكسي وحده موجود)"
            else:
                mir_cls, mir_reason = CLS_CONFLICT, \
                    "السحبة المقابلة ترتبط بمصروف آخر (expenseUuid)"
    elif is_sal:
        claimers = ctx["wd_by_exp_uuid"].get(row["uuid_key"], [])
        if len(claimers) == 1:
            matched_wd = claimers[0]["uuid_key"]
            mir_cls, mir_reason = CLS_REPAIRABLE, \
                "withdrawalUuid ناقص بالمصروف (السحبة تشير إليه عبر expenseUuid)"
        elif len(claimers) > 1:
            mir_cls, mir_reason = CLS_CONFLICT, \
                f"عدة سحبات ({len(claimers)}) تدّعي هذا المصروف عبر expenseUuid"
        else:
            mir_cls, mir_reason = CLS_ORPHAN, "مصروف رواتب بلا سحبة مقابل"

    worst = max([emp_cls, mir_cls], key=lambda c: CLASS_ORDER.index(c))
    return {
        "class": worst,
        "reason": " | ".join(x for x in (emp_reason, mir_reason) if x),
        "emp_cls": emp_cls, "emp_key": emp_key, "is_sal": is_sal,
        "matched_wd_uuid": matched_wd,
    }


# ============================================================
# 6) كتابة تقرير Excel — كاتب واحد (إصلاح F01) + تنسيق RTL
# ============================================================
MONEY_HEADER_KEYS = (
    "المبلغ", "الراتب", "الصافي", "سحوبات", "خصومات", "مصروفات_رواتب",
    "إجمالي", "اجمالي", "الأول", "الأخير",
)
COUNT_HEADER_KEYS = ("عدد", "مرشحون", "إصدارات")


def style_sheet(ws, df, nrows):
    """تنسيق مهني خفيف: رأس كحلي، تجميد، أعمدة بعرض معقول، أرقام مفصولة."""
    from openpyxl.styles import Alignment, Font, PatternFill

    ws.sheet_view.rightToLeft = True
    ncols = len(df.columns)

    # الرأس
    head_font = Font(name="Calibri", size=11, bold=True, color=STYLE_HEADER_TEXT)
    head_fill = PatternFill("solid", fgColor=STYLE_HEADER_FILL)
    for c in range(1, ncols + 1):
        cell = ws.cell(row=1, column=c)
        cell.font = head_font
        cell.fill = head_fill
        cell.alignment = Alignment(horizontal="center", vertical="center",
                                   wrap_text=True)
    ws.row_dimensions[1].height = 30
    ws.freeze_panes = "A2"

    # عرض الأعمدة (عيّنة حتى 200 صف) + تنسيقات الأرقام
    for c, name in enumerate(df.columns, start=1):
        letter = ws.cell(row=1, column=c).column_letter
        vals = df.iloc[:200, c - 1].astype(str)
        w = max([len(str(name))] + [len(v) for v in vals.tolist()[:200]] or [8])
        # العربية بحرف واحد عرضاً تقريباً — التقدير المباشر كافٍ
        ws.column_dimensions[letter].width = min(42, max(8, w + 2))
        if any(k in str(name) for k in MONEY_HEADER_KEYS):
            for r in range(2, nrows + 2):
                ws.cell(row=r, column=c).number_format = "#,##0"
        elif any(k in str(name) for k in COUNT_HEADER_KEYS):
            for r in range(2, nrows + 2):
                ws.cell(row=r, column=c).number_format = "#,##0"

    # صفوف متناوبة للجداول الصغيرة (حجم الملف محفوظ للكبيرة)
    if 0 < nrows <= ZEBRA_MAX_ROWS:
        zfill = PatternFill("solid", fgColor=STYLE_ZEBRA)
        body_font = Font(name="Calibri", size=11)
        for r in range(2, nrows + 2):
            if r % 2 == 1:
                for c in range(1, ncols + 1):
                    ws.cell(row=r, column=c).fill = zfill
                    ws.cell(row=r, column=c).font = body_font


def write_sheets(path, sheets):
    """كل الأوراق عبر كاتب واحد — لا كتّاب متداخلة أبداً (إصلاح F01)."""
    with pd.ExcelWriter(path, engine="openpyxl") as writer:
        for name, df in sheets:
            df.to_excel(writer, sheet_name=name, index=False)
            style_sheet(writer.sheets[name], df, len(df))
    return path


# ============================================================
# 7) البرنامج الرئيسي
# ============================================================
def main():
    args = sys.argv[1:]
    exp_path = find_file(args[0]) if len(args) > 0 else find_file(DEFAULT_EXPENSES)
    wd_path = find_file(args[1]) if len(args) > 1 else find_file(DEFAULT_WITHDRAWALS)
    emp_path = find_file(args[2]) if len(args) > 2 else find_file(DEFAULT_EMPLOYEES)
    out_path = args[3] if len(args) > 3 else DEFAULT_OUTPUT

    exp, wd, emp, cols = load_all(exp_path, wd_path, emp_path)
    print(f"   📊 الأعمدة المحلولة: {cols['wd_date']} للسحوبات، "
          f"{cols['emp_salary']} للرواتب")

    # ═══ كون الموظفين ═══
    print("\n👥 تجهيز الموظفين...")
    emp_p, emp_d, emp_live, by_uuid, by_server, deleted_uuids, sync_uuids, \
        emp_stats = build_employee_universe(emp, cols)
    print(f"   الموظفون: خام {emp_stats['raw']} → بعد إزالة التكرار "
          f"{emp_stats['dedup']} → تشغيليون {emp_stats['live']} "
          f"(محذوف ناعماً {emp_stats['deleted']}، مزامنة {emp_stats['sync']}، "
          f"تكرار localUuid {emp_stats['dup_localuuid']})")

    # ═══ تجهيز السحوبات والمصروفات ═══
    wd_p = prepare_frame(wd, cols["wd_id"], cols["wd_uuid"])
    wd_d = dedupe_latest(wd_p, "uuid_key")
    wd_live = wd_d[~wd_d["is_deleted"] & ~wd_d["is_sync_record"]].copy()
    print(f"\n💸 السحوبات: خام {len(wd)} → بعد إزالة التكرار {len(wd_d)} → "
          f"تشغيلية {len(wd_live)} "
          f"(محذوفة {int(wd_d['is_deleted'].sum())}، "
          f"مزامنة {int(wd_d['is_sync_record'].sum())})")

    exp_p = prepare_frame(exp, cols["exp_id"], cols["exp_uuid"])
    exp_d = dedupe_latest(exp_p, "uuid_key")
    exp_live = exp_d[~exp_d["is_deleted"] & ~exp_d["is_sync_record"]].copy()
    print(f"🧾 المصروفات: خام {len(exp)} → بعد إزالة التكرار {len(exp_d)} → "
          f"تشغيلية {len(exp_live)} "
          f"(محذوفة {int(exp_d['is_deleted'].sum())}، "
          f"مزامنة {int(exp_d['is_sync_record'].sum())})")

    # خرائط المصروفات للحلّ (الحاكم: localUuid ثم معرّف المستند)
    exp_by_uuid = {r["uuid_key"]: r for _, r in exp_live.iterrows()}
    exp_by_id = {r["id_str"]: r for _, r in exp_live.iterrows()}
    wd_by_uuid = {r["uuid_key"]: r for _, r in wd_live.iterrows()}
    wd_by_id = {r["id_str"]: r for _, r in wd_live.iterrows()}

    # المرايا الحية غير المطالَب بها (مرشحات التبنّي — هجرة 68 الطريقة 3)
    exp_candidates = []
    for _, r in exp_live.iterrows():
        if not salary_related(sstr(r[cols["exp_type"]])):
            continue
        if norm_uuid(r[cols["exp_wd_uuid"]]):
            continue  # مُطالَب بها بالفعل
        exp_candidates.append({
            "id_str": r["id_str"], "uuid_key": r["uuid_key"],
            "emp_key": norm_uuid(r[cols["exp_emp_uuid"]]),
            "amount": num(r[cols["exp_amount"]]),
            "date_str": sstr(r[cols["exp_date"]]),
            "hdk_str": sstr(r[cols["exp_hotel_day"]])
                       if cols.get("exp_hotel_day") else "",
        })

    # خريطة: مصروف تدّعيه عدة سحبات (لكشف التعارض العكسي)
    wd_by_exp_uuid = {}
    for _, r in wd_live.iterrows():
        eu = norm_uuid(r[cols["wd_exp_uuid"]])
        if eu:
            wd_by_exp_uuid.setdefault(eu, []).append(r)

    ctx = {
        "by_uuid": by_uuid, "by_server": by_server,
        "deleted_uuids": deleted_uuids, "sync_uuids": sync_uuids,
        "exp_by_uuid": exp_by_uuid, "exp_by_id": exp_by_id,
        "wd_by_uuid": wd_by_uuid, "wd_by_id": wd_by_id,
        "wd_by_exp_uuid": wd_by_exp_uuid, "exp_candidates": exp_candidates,
    }

    # ═══ تدقيق السحوبات التشغيلية ═══
    print("\n🔍 تدقيق السحوبات (الموظف + المرآة)...")
    wd_results = [audit_withdrawal(r, cols, ctx) for _, r in wd_live.iterrows()]
    wd_audit = pd.DataFrame(wd_results, index=wd_live.index).rename(
        columns={"class": "audit_class", "reason": "audit_reason",
                 "emp_cls": "audit_emp_cls", "emp_reason": "audit_emp_reason",
                 "mir_cls": "audit_mir_cls", "mir_reason": "audit_mir_reason",
                 "emp_key": "audit_emp_key", "emp_name": "audit_emp_name",
                 "matched_exp_id": "audit_matched_exp_id",
                 "matched_exp_uuid": "audit_matched_exp_uuid",
                 "candidates": "audit_candidates", "notes": "audit_notes"})
    wd_full = pd.concat([wd_live, wd_audit], axis=1)
    print("   " + " | ".join(
        f"{c}: {(wd_audit['audit_class'] == c).sum()}" for c in CLASS_ORDER))

    # ═══ تدقيق المصروفات التشغيلية ═══
    print("\n🔍 تدقيق المصروفات (الموظف + المرآة العكسية)...")
    exp_results = [audit_expense(r, cols, ctx) for _, r in exp_live.iterrows()]
    exp_audit = pd.DataFrame(exp_results, index=exp_live.index).rename(
        columns={"class": "audit_class", "reason": "audit_reason",
                 "emp_cls": "audit_emp_cls", "emp_key": "audit_emp_key",
                 "is_sal": "audit_is_sal",
                 "matched_wd_uuid": "audit_matched_wd_uuid"})
    exp_full = pd.concat([exp_live, exp_audit], axis=1)
    exp_sal = exp_full[exp_full["audit_is_sal"]]
    print(f"   مصروفات رواتب: {len(exp_sal)} — " + " | ".join(
        f"{c}: {(exp_sal['audit_class'] == c).sum()}" for c in CLASS_ORDER))

    # ═══ الاستحقاقات (نفس معادلة السكربت الأصلي — موثّقة بالمنهجية) ═══
    print("\n💰 حساب الاستحقاقات...")
    amt = pd.to_numeric(wd_full[cols["wd_amount"]], errors="coerce")
    wd_full["amount_num"] = amt
    wd_full["emp_key_resolved"] = wd_audit["audit_emp_key"]

    if len(wd_full):
        grouped = wd_full.groupby("emp_key_resolved")["amount_num"]
        ent = pd.DataFrame({
            "total_withdrawn": grouped.apply(lambda s: s[s > 0].sum()),
            "total_deductions": grouped.apply(lambda s: s[s < 0].sum()),
            "count": grouped.size(),
        }).reset_index().rename(columns={"emp_key_resolved": "uuid_key"})
    else:
        ent = pd.DataFrame(columns=["uuid_key", "total_withdrawn",
                                    "total_deductions", "count"])

    # مصروفات الرواتب المرتبطة بكل موظف (تدقيق الربط — جوهر المهمة)
    exp_amt = pd.to_numeric(exp_sal[cols["exp_amount"]], errors="coerce")
    if len(exp_sal):
        sal_exp_sum = exp_sal.assign(_a=exp_amt).groupby("audit_emp_key")[
            "_a"].agg(["sum", "count"]).reset_index().rename(
            columns={"audit_emp_key": "uuid_key",
                     "sum": "salary_expenses_total",
                     "count": "salary_expenses_count"})
    else:
        sal_exp_sum = pd.DataFrame(columns=["uuid_key",
                                            "salary_expenses_total",
                                            "salary_expenses_count"])

    emp_out = emp_live.copy()
    emp_out["salary_num"] = pd.to_numeric(
        emp_out[cols["emp_salary"]], errors="coerce").fillna(0)
    entitlements = emp_out[["uuid_key", cols.get("emp_name") or "name"]].rename(
        columns={cols.get("emp_name") or "name": "name"}).merge(
        ent, on="uuid_key", how="left").merge(
        sal_exp_sum, on="uuid_key", how="left")
    for c in ("total_withdrawn", "total_deductions",
              "salary_expenses_total", "salary_expenses_count"):
        if c in entitlements.columns:
            entitlements[c] = entitlements[c].fillna(0)
        else:
            entitlements[c] = 0
    entitlements["count"] = entitlements["count"].fillna(0).astype(int)
    entitlements["salary_num"] = (
        emp_out.set_index("uuid_key")["salary_num"]
        .reindex(entitlements["uuid_key"]).fillna(0).values)
    entitlements["net_balance"] = (
        entitlements["salary_num"]
        + entitlements["total_deductions"]   # سالبة
        - entitlements["total_withdrawn"]
    )

    # ═══ التكرارات (كل الجداول — تحسين عن الأصل الذي اكتفى بالسحوبات) ═══
    print("\n🔁 كشف الازدواجية...")
    dup_rows = []
    for label, frame, amount_col in (
        ("سحوبات", wd_p, cols["wd_amount"]),
        ("مصروفات", exp_p, cols["exp_amount"]),
        ("موظفون", emp_p, None),
    ):
        key = "uuid_key" if "uuid_key" in frame.columns else None
        if key is None:
            continue
        grp = frame[frame[key] != ""].groupby(key, sort=False)
        for k, g in grp:
            if len(g) <= 1:
                continue
            versions = pd.to_numeric(
                g["version"], errors="coerce").nunique() if "version" in g.columns else 1
            a = g[amount_col].astype(str).tolist() if amount_col else []
            dup_rows.append({
                "الجدول": label, "localUuid": k, "عدد الصفوف": len(g),
                "عدد الإصدارات": int(versions),
                "المبلغ الأول": a[0] if a else "",
                "المبلغ الأخير": a[-1] if a else "",
                "معرفات المستندات": "، ".join(g["id_str"].tolist()[:8]),
            })
    dup_summary = pd.DataFrame(dup_rows, columns=[
        "الجدول", "localUuid", "عدد الصفوف", "عدد الإصدارات",
        "المبلغ الأول", "المبلغ الأخير", "معرفات المستندات"])
    if not dup_summary.empty:
        dup_summary = dup_summary.sort_values(
            ["الجدول", "عدد الصفوف"], ascending=[True, False])
    print(f"   مجموعات مكررة: {len(dup_summary)}")

    # ═══ السجلات اليتيمة (تشغيلية فقط — إصلاح F10) ═══
    print("\n🗑  السجلات اليتيمة...")
    orphan_wd_emp = wd_full[wd_full["audit_emp_cls"] == CLS_ORPHAN]
    orphan_exp_emp = exp_full[exp_full["audit_emp_cls"] == CLS_ORPHAN]
    orphan_wd_exp = wd_full[
        wd_full["audit_mir_cls"].isin([CLS_ORPHAN, CLS_AMBIGUOUS])]
    print(f"   سحوبات لموظف غير موجود: {len(orphan_wd_emp)}")
    print(f"   مصروفات لموظف غير موجود: {len(orphan_exp_emp)}")
    print(f"   سحوبات بلا مصروف مقابل (يتيمة/غامضة): {len(orphan_wd_exp)}")

    # ═══ الحالات الشاذة ═══
    print("\n⚠️  الحالات الشاذة...")
    big_wd = wd_full[wd_full["amount_num"] >= BIG_WITHDRAWAL].sort_values(
        "amount_num", ascending=False)
    exp_full["amount_num"] = pd.to_numeric(
        exp_full[cols["exp_amount"]], errors="coerce")
    big_exp = exp_full[exp_full["amount_num"] >= BIG_EXPENSE].sort_values(
        "amount_num", ascending=False)
    backfill_exp = exp_p[exp_p["id_str"].str.lower().str.startswith(
        "backfill")].drop_duplicates(subset=["id_str"])
    print(f"   سحوبات ≥ {BIG_WITHDRAWAL}: {len(big_wd)} | "
          f"مصروفات ≥ {BIG_EXPENSE}: {len(big_exp)} | "
          f"مستندات backfill: {len(backfill_exp)}")

    # ═══ فحص تنسيقات الروابط (بديل فحص expenseId الأحادي — إصلاح F12) ═══
    link_rows = []

    def add_link(table, check, result, n):
        link_rows.append({"الجدول": table, "الفحص": check,
                          "النتيجة": result, "العدد": int(n)})

    wu = wd_live[cols["wd_exp_uuid"]].map(norm_uuid)
    add_link("سحوبات", "expenseUuid", "UUID صالح", wu.map(is_uuid).sum())
    add_link("سحوبات", "expenseUuid", "تنسيق غير صالح (موجود لكنه ليس UUID)",
             (wu != "").sum() - wu.map(is_uuid).sum())
    add_link("سحوبات", "expenseUuid", "فارغ", (wu == "").sum())
    if cols.get("wd_exp_id"):
        eid = wd_live[cols["wd_exp_id"]].map(num)
        add_link("سحوبات", "expenseId التراثي", "رقمي (مرجع جهاز المصدر)",
                 eid.notna().sum())
        add_link("سحوبات", "expenseId التراثي", "فارغ/غير رقمي",
                 eid.isna().sum())
    if cols.get("wd_reason"):
        rs = wd_live[cols["wd_reason"]].map(sstr)
        add_link("سحوبات", "reason", "بنمط exp_N", rs.map(
            lambda s: bool(REASON_RE.match(s))).sum())
        add_link("سحوبات", "reason", "نص آخر / فارغ", (~rs.map(
            lambda s: bool(REASON_RE.match(s)))).sum())
        # تناسق reason↔expenseId
        mism = consistent_reason = 0
        for _, r in wd_live.iterrows():
            m = REASON_RE.match(sstr(r[cols["wd_reason"]]))
            eidv = num(r[cols["wd_exp_id"]]) if cols.get("wd_exp_id") else None
            if m and eidv is not None:
                if int(m.group(1)) == int(eidv):
                    consistent_reason += 1
                else:
                    mism += 1
        add_link("سحوبات", "تناسق reason↔expenseId", "متسق", consistent_reason)
        add_link("سحوبات", "تناسق reason↔expenseId", "متعارض", mism)
    eu = exp_live[cols["exp_wd_uuid"]].map(norm_uuid)
    add_link("مصروفات", "withdrawalUuid", "UUID صالح", eu.map(is_uuid).sum())
    add_link("مصروفات", "withdrawalUuid", "تنسيق غير صالح",
             (eu != "").sum() - eu.map(is_uuid).sum())
    add_link("مصروفات", "withdrawalUuid", "فارغ", (eu == "").sum())
    xu = exp_live[cols["exp_emp_uuid"]].map(norm_uuid)
    add_link("مصروفات", "employeeUuid", "UUID صالح", xu.map(is_uuid).sum())
    add_link("مصروفات", "employeeUuid", "موجود غير قياسي", (
        (xu != "") & ~xu.map(is_uuid)).sum())
    add_link("مصروفات", "employeeUuid", "فارغ", (xu == "").sum())
    if cols.get("emp_server_id"):
        sv = emp_live[cols["emp_server_id"]].map(num)
        add_link("موظفون", "serverId", "رقمي", sv.notna().sum())
        add_link("موظفون", "serverId", "فارغ/غير رقمي", sv.isna().sum())
    link_check = pd.DataFrame(link_rows, columns=[
        "الجدول", "الفحص", "النتيجة", "العدد"])

    # ═══ جدول التصنيف ═══
    cls_rows = []
    for label, sub in (("سحوبات تشغيلية", wd_audit["audit_class"]),
                       ("مصروفات رواتب تشغيلية", exp_sal["audit_class"]),
                       ("مصروفات عامة تشغيلية",
                        exp_full.loc[~exp_full["audit_is_sal"],
                                     "audit_class"])):
        row = {"الفئة": label}
        for c in CLASS_ORDER:
            row[c] = int((sub == c).sum())
        row["الإجمالي"] = int(len(sub))
        cls_rows.append(row)
    cls_table = pd.DataFrame(cls_rows)

    # ═══ ورقة التعارضات (قرار بشري — لا تخمين) ═══
    conf_rows = []
    for _, r in wd_full[wd_full["audit_class"] == CLS_CONFLICT].iterrows():
        conf_rows.append({
            "الجدول": "سحوبات", "المعرف": r["id_str"],
            "localUuid": r["uuid_key"], "الموظف": r["audit_emp_name"],
            "UUID الموظف": r["audit_emp_key"],
            "المبلغ": r["amount_num"], "السبب": r["audit_reason"],
        })
    for _, r in exp_full[exp_full["audit_class"] == CLS_CONFLICT].iterrows():
        conf_rows.append({
            "الجدول": "مصروفات", "المعرف": r["id_str"],
            "localUuid": r["uuid_key"], "الموظف": "",
            "UUID الموظف": r["audit_emp_key"],
            "المبلغ": r["amount_num"], "السبب": r["audit_reason"],
        })
    conflicts = pd.DataFrame(conf_rows, columns=[
        "الجدول", "المعرف", "localUuid", "الموظف", "UUID الموظف",
        "المبلغ", "السبب"])

    # ═══ الملخص ═══
    summary = pd.DataFrame({
        "البند": [
            "إجمالي الموظفين (خام)",
            "الموظفون بعد إزالة التكرار",
            "الموظفون النشطون (تشغيليون)",
            "إجمالي الرواتب الشهرية للنشطين",
            "عدد سحوبات الرواتب (تشغيلي)",
            "إجمالي السحوبات",
            "إجمالي الخصومات (سجلات سالبة)",
            "صافي الاستحقاق الكلي",
            "عدد سجلات المصروفات (تشغيلي)",
            "إجمالي المصروفات",
            "مصروفات الرواتب (تشغيلي)",
            "سحوبات لها مرآة متبادلة سليمة",
            "سحوبات بلا مصروف مقابل (يتيمة/غامضة)",
            "سحوبات مكررة (localUuid)",
            "سجلات محذوفة ناعماً (سحوبات/مصروفات/موظفون)",
            "سجلات مزامنة/نسخ احتياطي (سحوبات/مصروفات/موظفون)",
            "تعارضات تحتاج قراراً بشرياً",
        ],
        "القيمة": [
            len(emp), emp_stats["dedup"], emp_stats["live"],
            pd.to_numeric(emp_live[cols["emp_salary"]],
                          errors="coerce").fillna(0).sum(),
            len(wd_full),
            wd_full.loc[wd_full["amount_num"] > 0, "amount_num"].sum(),
            wd_full.loc[wd_full["amount_num"] < 0, "amount_num"].sum(),
            entitlements["net_balance"].sum(),
            len(exp_full),
            exp_full["amount_num"].sum(),
            len(exp_sal),
            int((wd_audit["audit_mir_cls"] == CLS_OK).sum()),
            len(orphan_wd_exp),
            int((dup_summary["الجدول"] == "سحوبات").sum()) if not dup_summary.empty else 0,
            f"{int(wd_d['is_deleted'].sum())}/{int(exp_d['is_deleted'].sum())}"
            f"/{emp_stats['deleted']}",
            f"{int(wd_d['is_sync_record'].sum())}/"
            f"{int(exp_d['is_sync_record'].sum())}/{emp_stats['sync']}",
            len(conflicts),
        ],
    })

    methodology = pd.DataFrame({
        "المنهجية": [
            "🔴 قراءة فقط — لا كتابة على Appwrite ولا على أي مصدر بيانات.",
            "الرابط الحاكم (هجرة 68): سحبة.expenseUuid ↔ مصروف.localUuid، "
            "والعكس بالمصروف عبر withdrawalUuid؛ الاسم/اليوم/المبلغ ليست هوية.",
            "حرّاس إعادة البناء (backfill_withdrawal_expense_uuid.py): نفس "
            "الموظف + نفس المبلغ ±0.005 + نفس اليوم + فرادة المرشح.",
            "employeeUuid يفوز دائماً (employee_link_consistency_service.dart)؛ "
            "لا تخمين لأي مالك — الغامض واليتيم يُعرضان لقرار بشري.",
            "expenseId الرقمي = مرجع جهاز المصدر (غير محمول عبر الأجهزة) — "
            "يُفحص تنسيقه وتناسقه مع reason=exp_N فقط.",
            "وعي الحذف الناعم deletedAt: المحذوف يُستثنى من التجميع التشغيلي "
            "ويُحصى منفصلاً (منهجية audit_full_mirror.py).",
            "معادلة الاستحقاق هنا: الراتب + الخصومات(سالبة) − السحوبات — "
            "معادلة تدقيق مبسطة؛ استحقاق التطبيق الفعلي (SalaryEntitlementService) "
            "دوريّ ويشمل السلف والترحيلات ومصروفات الخصم، ولا يمكن استنساخه "
            "من هذه الملفات الثلاثة وحدها.",
        ],
    })

    # ═══ أوراق الخرج (بنية الأصل محفوظة + ورقتان جديدتان) ═══
    def pick(d, mapping):
        out = pd.DataFrame(index=d.index)
        for dst, src in mapping.items():
            out[dst] = d[src] if src in d.columns else ""
        return out

    sheets = [
        ("الاستحقاقات", pick(entitlements, {
            "uuid_key": "uuid_key", "الاسم": "name",
            "الراتب": "salary_num", "إجمالي السحوبات": "total_withdrawn",
            "إجمالي الخصومات": "total_deductions",
            "مصروفات رواتب مرتبطة": "salary_expenses_total",
            "عدد مصروفات الرواتب": "salary_expenses_count",
            "الصافي (معادلة التدقيق)": "net_balance", "عدد السحوبات": "count",
        })),
        ("الموظفون", pick(emp_out, {
            "uuid_key": "uuid_key", "المعرف": "id_str",
            "الاسم": cols.get("emp_name") or "name",
            "المسمى": cols.get("emp_position") or "position",
            "الحالة": cols.get("emp_status") or "status",
            "الراتب": "salary_num",
            "serverId": cols.get("emp_server_id") or "serverId",
            "تاريخ التعيين": cols.get("emp_hire") or "hireDate",
            "تاريخ الإنهاء": cols.get("emp_term") or "terminationDate",
        })),
        ("السحوبات", pick(wd_full, {
            "المعرف": "id_str", "localUuid": "uuid_key",
            "الموظف": "audit_emp_name", "UUID الموظف": "audit_emp_key",
            "المبلغ": "amount_num", "النوع": cols["wd_type"],
            "التاريخ": cols["wd_date"],
            "الوصف": cols.get("wd_desc") or "description",
            "expenseUuid": cols["wd_exp_uuid"],
            "expenseId التراثي": cols.get("wd_exp_id") or "expenseId",
            "reason": cols.get("wd_reason") or "reason",
            "المرآة المطابقة": "audit_matched_exp_id",
            "التصنيف": "audit_class", "السبب": "audit_reason",
        })),
        ("المصروفات", pick(exp_full, {
            "المعرف": "id_str", "localUuid": "uuid_key",
            "UUID الموظف": "audit_emp_key", "المبلغ": "amount_num",
            "النوع": cols["exp_type"], "التاريخ": cols["exp_date"],
            "الوصف": cols.get("exp_desc") or "description",
            "withdrawalUuid": cols["exp_wd_uuid"],
            "السحبة المطابقة": "audit_matched_wd_uuid",
            "التصنيف": "audit_class", "السبب": "audit_reason",
        })),
        ("التكرارات", dup_summary),
        ("يتيمة_سحوبات_موظف", pick(orphan_wd_emp, {
            "المعرف": "id_str", "localUuid": "uuid_key",
            "UUID الموظف المفقود": "audit_emp_key", "المبلغ": "amount_num",
            "التاريخ": cols["wd_date"], "السبب": "audit_emp_reason",
        })),
        ("يتيمة_مصروفات_موظف", pick(orphan_exp_emp, {
            "المعرف": "id_str", "localUuid": "uuid_key",
            "UUID الموظف المفقود": "audit_emp_key", "المبلغ": "amount_num",
            "النوع": cols["exp_type"], "السبب": "audit_emp_reason",
        })),
        ("سحوبات_بلا_مصروف", pick(orphan_wd_exp, {
            "المعرف": "id_str", "localUuid": "uuid_key",
            "الموظف": "audit_emp_name", "UUID الموظف": "audit_emp_key",
            "المبلغ": "amount_num", "التاريخ": cols["wd_date"],
            "عدد المرشحين": "audit_candidates", "السبب": "audit_mir_reason",
        })),
        ("سحوبات_كبيرة", pick(big_wd, {
            "المعرف": "id_str", "الموظف": "audit_emp_name",
            "المبلغ": "amount_num", "التاريخ": cols["wd_date"],
            "التصنيف": "audit_class",
        })),
        ("مصروفات_كبيرة", pick(big_exp, {
            "المعرف": "id_str", "UUID الموظف": "audit_emp_key",
            "المبلغ": "amount_num", "النوع": cols["exp_type"],
            "التاريخ": cols["exp_date"], "التصنيف": "audit_class",
        })),
        ("backfill_ديزل", pick(backfill_exp, {
            "المعرف": "id_str", "localUuid": "uuid_key",
            "المبلغ": cols["exp_amount"], "التاريخ": cols["exp_date"],
            "الوصف": cols.get("exp_desc") or "description",
        })),
        ("فحص_الروابط", link_check),
        ("التصنيف", cls_table),
        ("تعارضات", conflicts),
        ("الملخص", summary),
        ("المنهجية", methodology),
    ]

    print(f"\n📝 كتابة التقرير: {out_path}")
    write_sheets(out_path, sheets)
    print(f"✅ تم إنشاء التقرير: {out_path} "
          f"({len(sheets)} ورقة، قراءة فقط — لا كتابة سحابية)")

    print("\n📊 ملخص سريع:")
    print(summary.to_string(index=False))
    print("\n🔢 التصنيف:")
    print(cls_table.to_string(index=False))


if __name__ == "__main__":
    main()
