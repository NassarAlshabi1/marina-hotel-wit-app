const { Document, Packer, Paragraph, TextRun, Table, TableRow, TableCell, HeadingLevel, AlignmentType, BorderStyle, WidthType, ShadingType, VerticalAlign, Header, Footer, PageNumber, LevelFormat, PageBreak } = require('docx');
const fs = require('fs');

// Colors - Midnight Code theme
const colors = {
  primary: "020617",
  body: "1E293B",
  secondary: "64748B",
  accent: "94A3B8",
  tableBg: "F8FAFC"
};

// Table borders
const tableBorder = { style: BorderStyle.SINGLE, size: 1, color: "CCCCCC" };
const cellBorders = { top: tableBorder, bottom: tableBorder, left: tableBorder, right: tableBorder };

// Helper function to create table cell
function cell(text, isHeader = false, width = 2340) {
  return new TableCell({
    borders: cellBorders,
    width: { size: width, type: WidthType.DXA },
    shading: isHeader ? { fill: colors.tableBg, type: ShadingType.CLEAR } : undefined,
    verticalAlign: VerticalAlign.CENTER,
    children: [new Paragraph({
      alignment: AlignmentType.CENTER,
      children: [new TextRun({ 
        text, 
        bold: isHeader, 
        size: isHeader ? 22 : 20,
        font: "SimSun"
      })]
    })]
  });
}

// Create collection field table
function createFieldTable(fields) {
  const rows = [
    new TableRow({
      tableHeader: true,
      children: [
        cell("اسم الحقل", true, 3000),
        cell("النوع", true, 2000),
        cell("مطلوب", true, 1500),
        cell("الوصف", true, 2860)
      ]
    })
  ];
  
  fields.forEach(f => {
    rows.push(new TableRow({
      children: [
        cell(f.name, false, 3000),
        cell(f.type, false, 2000),
        cell(f.required, false, 1500),
        cell(f.desc, false, 2860)
      ]
    }));
  });
  
  return new Table({
    columnWidths: [3000, 2000, 1500, 2860],
    margins: { top: 100, bottom: 100, left: 150, right: 150 },
    rows
  });
}

// Sync fields that every synced table should have
const syncFields = [
  { name: "localUuid", type: "String", required: "نعم", desc: "المعرف الفريد المحلي (UUID)" },
  { name: "serverId", type: "Integer", required: "لا", desc: "معرف الخادم (إن وجد)" },
  { name: "createdAt", type: "Integer", required: "نعم", desc: "تاريخ الإنشاء (Epoch)" },
  { name: "updatedAt", type: "Integer", required: "نعم", desc: "تاريخ التحديث (Epoch)" },
  { name: "deletedAt", type: "Integer", required: "لا", desc: "تاريخ الحذف (Epoch)" },
  { name: "lastModified", type: "Integer", required: "نعم", desc: "آخر تعديل (Epoch)" },
  { name: "version", type: "Integer", required: "نعم", desc: "رقم الإصدار" },
  { name: "origin", type: "String", required: "نعم", desc: "مصدر البيانات (local/server)" },
  { name: "vectorClock", type: "String", required: "نعم", desc: "ساعة المتجهات للمزامنة" }
];

// salary_withdrawals fields
const salaryWithdrawalsFields = [
  { name: "id", type: "Integer", required: "نعم", desc: "المعرف المحلي التلقائي" },
  { name: "expenseId", type: "Integer", required: "لا", desc: "معرف المصروف المرتبط" },
  { name: "employeeId", type: "Integer", required: "نعم", desc: "معرف الموظف" },
  { name: "action", type: "String", required: "نعم", desc: "نوع الإجراء (سحب راتب/خصم)" },
  { name: "amount", type: "Integer", required: "نعم", desc: "المبلغ (بالدينار)" },
  { name: "note", type: "String", required: "لا", desc: "ملاحظات" },
  { name: "date", type: "String", required: "نعم", desc: "تاريخ السحب" },
  ...syncFields
];

const doc = new Document({
  styles: {
    default: { document: { run: { font: "SimSun", size: 24 } } },
    paragraphStyles: [
      { id: "Title", name: "Title", basedOn: "Normal",
        run: { size: 48, bold: true, color: colors.primary, font: "SimHei" },
        paragraph: { spacing: { before: 240, after: 200 }, alignment: AlignmentType.CENTER } },
      { id: "Heading1", name: "Heading 1", basedOn: "Normal", next: "Normal", quickFormat: true,
        run: { size: 32, bold: true, color: colors.primary, font: "SimHei" },
        paragraph: { spacing: { before: 360, after: 200 }, outlineLevel: 0 } },
      { id: "Heading2", name: "Heading 2", basedOn: "Normal", next: "Normal", quickFormat: true,
        run: { size: 28, bold: true, color: colors.body, font: "SimHei" },
        paragraph: { spacing: { before: 280, after: 160 }, outlineLevel: 1 } },
      { id: "Heading3", name: "Heading 3", basedOn: "Normal", next: "Normal", quickFormat: true,
        run: { size: 24, bold: true, color: colors.secondary, font: "SimHei" },
        paragraph: { spacing: { before: 200, after: 120 }, outlineLevel: 2 } }
    ]
  },
  sections: [{
    properties: {
      page: { margin: { top: 1440, right: 1440, bottom: 1440, left: 1440 } }
    },
    headers: {
      default: new Header({ children: [new Paragraph({
        alignment: AlignmentType.CENTER,
        children: [new TextRun({ text: "Marina Hotel - Appwrite Collections Guide", font: "SimHei", size: 20, color: colors.secondary })]
      })] })
    },
    footers: {
      default: new Footer({ children: [new Paragraph({
        alignment: AlignmentType.CENTER,
        children: [
          new TextRun({ text: "صفحة ", font: "SimSun", size: 20 }),
          new TextRun({ children: [PageNumber.CURRENT], font: "SimSun", size: 20 }),
          new TextRun({ text: " من ", font: "SimSun", size: 20 }),
          new TextRun({ children: [PageNumber.TOTAL_PAGES], font: "SimSun", size: 20 })
        ]
      })] })
    },
    children: [
      // Title
      new Paragraph({
        heading: HeadingLevel.TITLE,
        children: [new TextRun({ text: "دليل Collections في Appwrite", font: "SimHei" })]
      }),
      new Paragraph({
        alignment: AlignmentType.CENTER,
        spacing: { after: 400 },
        children: [new TextRun({ text: "Marina Hotel Sync System", font: "SimSun", size: 22, color: colors.secondary })]
      }),
      
      // Section 1: Overview
      new Paragraph({ heading: HeadingLevel.HEADING_1, children: [new TextRun("نظرة عامة")] }),
      new Paragraph({
        alignment: AlignmentType.JUSTIFIED,
        indent: { firstLine: 480 },
        spacing: { line: 312 },
        children: [new TextRun({ text: "يستخدم تطبيق Marina Hotel نظام مزامنة تفاضلية مع Appwrite Cloud. تتطلب المزامنة إنشاء Collections في قاعدة البيانات hotel_db مع حقول محددة تتطابق مع الـ Schema المحلي. هذا الدليل يوضح جميع الـ Collections المطلوبة والحقول الخاصة بكل منها.", font: "SimSun" })]
      }),
      
      // Section 2: Connection Info
      new Paragraph({ heading: HeadingLevel.HEADING_1, children: [new TextRun("معلومات الاتصال")] }),
      new Paragraph({
        spacing: { line: 312 },
        children: [new TextRun({ text: "Endpoint: ", bold: true, font: "SimSun" }), new TextRun({ text: "https://fra.cloud.appwrite.io/v1", font: "SimSun" })]
      }),
      new Paragraph({
        spacing: { line: 312 },
        children: [new TextRun({ text: "Project ID: ", bold: true, font: "SimSun" }), new TextRun({ text: "690ff0da0025518570c1", font: "SimSun" })]
      }),
      new Paragraph({
        spacing: { line: 312 },
        children: [new TextRun({ text: "Database ID: ", bold: true, font: "SimSun" }), new TextRun({ text: "hotel_db", font: "SimSun" })]
      }),
      
      // Section 3: Collections List
      new Paragraph({ heading: HeadingLevel.HEADING_1, children: [new TextRun("قائمة Collections المطلوبة")] }),
      new Paragraph({
        alignment: AlignmentType.JUSTIFIED,
        indent: { firstLine: 480 },
        spacing: { line: 312 },
        children: [new TextRun({ text: "يتم مزامنة الـ Collections التالية بين التطبيق و Appwrite. يجب التأكد من وجود جميع هذه الـ Collections مع الحقول الصحيحة:", font: "SimSun" })]
      }),
      
      new Table({
        columnWidths: [4000, 3000, 2360],
        margins: { top: 100, bottom: 100, left: 150, right: 150 },
        rows: [
          new TableRow({
            tableHeader: true,
            children: [
              cell("اسم Collection", true, 4000),
              cell("Collection ID", true, 3000),
              cell("الحالة", true, 2360)
            ]
          }),
          ...["rooms|rooms|موجود",
              "bookings|bookings|موجود",
              "payments|payments|موجود",
              "expenses|expenses|موجود",
              "employees|employees|موجود",
              "debts|debts|موجود",
              "booking_notes|booking_notes|موجود",
              "booking_nights|booking_nights|موجود",
              "cash_transactions|cash_transactions|موجود",
              "salary_cycles|salary_cycles|موجود",
              "salary_payments|salary_payments|موجود",
              "salary_withdrawals|salary_withdrawals|⚠️ جديد",
              "shift_notes|shift_notes|موجود"].map(line => {
            const [name, id, status] = line.split("|");
            return new TableRow({
              children: [
                cell(name, false, 4000),
                cell(id, false, 3000),
                cell(status, false, 2360)
              ]
            });
          })
        ]
      }),
      
      new Paragraph({ spacing: { after: 200 }, children: [] }),
      
      // Section 4: salary_withdrawals (NEW - IMPORTANT)
      new Paragraph({ heading: HeadingLevel.HEADING_1, children: [new TextRun("⚠️ Collection جديد: salary_withdrawals")] }),
      new Paragraph({
        alignment: AlignmentType.JUSTIFIED,
        indent: { firstLine: 480 },
        spacing: { line: 312 },
        children: [new TextRun({ text: "تمت إضافة جدول سحوبات الرواتب حديثاً لنظام المزامنة. هذا الـ Collection يجب إنشاؤه في Appwrite مع الحقول التالية:", font: "SimSun" })]
      }),
      
      new Paragraph({ heading: HeadingLevel.HEADING_2, children: [new TextRun("خطوات إنشاء Collection")] }),
      new Paragraph({
        spacing: { line: 312 },
        children: [new TextRun({ text: "1. انتقل إلى Appwrite Console > Databases > hotel_db", font: "SimSun" })]
      }),
      new Paragraph({
        spacing: { line: 312 },
        children: [new TextRun({ text: "2. انقر على \"Create Collection\"", font: "SimSun" })]
      }),
      new Paragraph({
        spacing: { line: 312 },
        children: [new TextRun({ text: "3. أدخل Collection ID: salary_withdrawals", font: "SimSun" })]
      }),
      new Paragraph({
        spacing: { line: 312 },
        children: [new TextRun({ text: "4. أضف الحقول التالية:", font: "SimSun" })]
      }),
      
      new Paragraph({ heading: HeadingLevel.HEADING_2, children: [new TextRun("الحقول المطلوبة")] }),
      createFieldTable(salaryWithdrawalsFields),
      
      new Paragraph({ spacing: { after: 200 }, children: [] }),
      new Paragraph({ heading: HeadingLevel.HEADING_2, children: [new TextRun("الصلاحيات المطلوبة")] }),
      new Paragraph({
        alignment: AlignmentType.JUSTIFIED,
        indent: { firstLine: 480 },
        spacing: { line: 312 },
        children: [new TextRun({ text: "يجب تعيين الصلاحيات التالية للـ Collection:", font: "SimSun" })]
      }),
      new Paragraph({
        spacing: { line: 312 },
        children: [new TextRun({ text: "• Documents: Create, Read, Update, Delete (للمستخدمين المصادق عليهم)", font: "SimSun" })]
      }),
      new Paragraph({
        spacing: { line: 312 },
        children: [new TextRun({ text: "• Attributes: جميع الحقول قابلة للقراءة والكتابة", font: "SimSun" })]
      }),
      
      // Section 5: SyncFields reference
      new Paragraph({ heading: HeadingLevel.HEADING_1, children: [new TextRun("الحقول المشتركة للمزامنة (SyncFields)")] }),
      new Paragraph({
        alignment: AlignmentType.JUSTIFIED,
        indent: { firstLine: 480 },
        spacing: { line: 312 },
        children: [new TextRun({ text: "جميع الـ Collections التي تدعم المزامنة يجب أن تحتوي على الحقول التالية بالإضافة للحقول الخاصة بكل جدول:", font: "SimSun" })]
      }),
      createFieldTable(syncFields),
      
      new Paragraph({ spacing: { after: 200 }, children: [] }),
      
      // Section 6: Verification Steps
      new Paragraph({ heading: HeadingLevel.HEADING_1, children: [new TextRun("خطوات التحقق من المزامنة")] }),
      new Paragraph({
        alignment: AlignmentType.JUSTIFIED,
        indent: { firstLine: 480 },
        spacing: { line: 312 },
        children: [new TextRun({ text: "بعد إنشاء أو تحديث Collections في Appwrite، اتبع الخطوات التالية للتحقق من صحة المزامنة:", font: "SimSun" })]
      }),
      new Paragraph({
        spacing: { line: 312 },
        children: [new TextRun({ text: "1. تأكد من تشغيل flutter pub run build_runner build --delete-conflicting-outputs", font: "SimSun" })]
      }),
      new Paragraph({
        spacing: { line: 312 },
        children: [new TextRun({ text: "2. أعد تشغيل التطبيق", font: "SimSun" })]
      }),
      new Paragraph({
        spacing: { line: 312 },
        children: [new TextRun({ text: "3. قم بعملية مزامنة (Push/Pull)", font: "SimSun" })]
      }),
      new Paragraph({
        spacing: { line: 312 },
        children: [new TextRun({ text: "4. تحقق من Logs للتأكد من عدم وجود أخطاء", font: "SimSun" })]
      }),
      
      // Section 7: Troubleshooting
      new Paragraph({ heading: HeadingLevel.HEADING_1, children: [new TextRun("استكشاف الأخطاء")] }),
      new Paragraph({ heading: HeadingLevel.HEADING_2, children: [new TextRun("خطأ: Collection not found")] }),
      new Paragraph({
        alignment: AlignmentType.JUSTIFIED,
        indent: { firstLine: 480 },
        spacing: { line: 312 },
        children: [new TextRun({ text: "السبب: الـ Collection غير موجود في Appwrite. الحل: قم بإنشاء الـ Collection المطلوب مع الحقول الصحيحة.", font: "SimSun" })]
      }),
      new Paragraph({ heading: HeadingLevel.HEADING_2, children: [new TextRun("خطأ: Attribute not found")] }),
      new Paragraph({
        alignment: AlignmentType.JUSTIFIED,
        indent: { firstLine: 480 },
        spacing: { line: 312 },
        children: [new TextRun({ text: "السبب: حقل مطلوب غير موجود في الـ Collection. الحل: أضف الحقل المفقود في Appwrite Console.", font: "SimSun" })]
      }),
      new Paragraph({ heading: HeadingLevel.HEADING_2, children: [new TextRun("خطأ: Permission denied")] }),
      new Paragraph({
        alignment: AlignmentType.JUSTIFIED,
        indent: { firstLine: 480 },
        spacing: { line: 312 },
        children: [new TextRun({ text: "السبب: صلاحيات غير كافية. الحل: راجع إعدادات الصلاحيات في Collection Settings.", font: "SimSun" })]
      }),
      
      new Paragraph({ spacing: { after: 400 }, children: [] }),
      
      // Footer note
      new Paragraph({
        alignment: AlignmentType.CENTER,
        children: [new TextRun({ text: "تم إنشاء هذا الدليل تلقائياً من كود التطبيق", font: "SimSun", size: 18, color: colors.secondary })]
      })
    ]
  }]
});

Packer.toBuffer(doc).then(buffer => {
  fs.writeFileSync("/home/z/my-project/download/appwrite_collections_guide.docx", buffer);
  console.log("Document created successfully!");
});
