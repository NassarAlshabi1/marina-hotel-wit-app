<?php
session_start();
require_once '../../includes/db.php';

echo "<h2>فحص قاعدة البيانات</h2>";

// فحص الجداول المطلوبة
$required_tables = [
    'expenses',
    'salary_withdrawals', 
    'expense_logs',
    'employees',
    'suppliers'
];

echo "<h3>الجداول الموجودة:</h3>";
foreach ($required_tables as $table) {
    $result = $conn->query("SHOW TABLES LIKE '$table'");
    if ($result->num_rows > 0) {
        echo "✅ $table موجود<br>";
        
        // عرض بنية الجدول
        echo "<details><summary>عرض أعمدة $table</summary>";
        $columns = $conn->query("SHOW COLUMNS FROM $table");
        echo "<table border='1'>";
        echo "<tr><th>العمود</th><th>النوع</th><th>NULL</th><th>المفتاح</th><th>الافتراضي</th></tr>";
        while ($col = $columns->fetch_assoc()) {
            echo "<tr>";
            echo "<td>{$col['Field']}</td>";
            echo "<td>{$col['Type']}</td>";
            echo "<td>{$col['Null']}</td>";
            echo "<td>{$col['Key']}</td>";
            echo "<td>{$col['Default']}</td>";
            echo "</tr>";
        }
        echo "</table></details><br>";
    } else {
        echo "❌ $table غير موجود<br>";
    }
}

// إنشاء الجداول المفقودة
echo "<h3>إنشاء الجداول المفقودة:</h3>";

// جدول salary_withdrawals (بدون created_by و created_at)
$check_salary_withdrawals = $conn->query("SHOW TABLES LIKE 'salary_withdrawals'");
if ($check_salary_withdrawals->num_rows == 0) {
    $create_salary_withdrawals = "
    CREATE TABLE salary_withdrawals (
        id INT AUTO_INCREMENT PRIMARY KEY,
        employee_id INT NOT NULL,
        amount DECIMAL(10,2) NOT NULL,
        date DATE NOT NULL,
        notes TEXT,
        withdrawal_type VARCHAR(50) DEFAULT 'cash',
        INDEX idx_employee_id (employee_id),
        INDEX idx_date (date)
    )";
    
    if ($conn->query($create_salary_withdrawals)) {
        echo "✅ تم إنشاء جدول salary_withdrawals<br>";
    } else {
        echo "❌ خطأ في إنشاء جدول salary_withdrawals: " . $conn->error . "<br>";
    }
}

// جدول expense_logs (بدون user_id و created_at)
$check_expense_logs = $conn->query("SHOW TABLES LIKE 'expense_logs'");
if ($check_expense_logs->num_rows == 0) {
    $create_expense_logs = "
    CREATE TABLE expense_logs (
        id INT AUTO_INCREMENT PRIMARY KEY,
        expense_id INT NOT NULL,
        action VARCHAR(50) NOT NULL,
        details TEXT,
        INDEX idx_expense_id (expense_id),
        INDEX idx_action (action)
    )";
    
    if ($conn->query($create_expense_logs)) {
        echo "✅ تم إنشاء جدول expense_logs<br>";
    } else {
        echo "❌ خطأ في إنشاء جدول expense_logs: " . $conn->error . "<br>";
    }
}

// التحقق من أعمدة جدول employees
$check_employees = $conn->query("SHOW COLUMNS FROM employees LIKE 'basic_salary'");
if ($check_employees->num_rows == 0) {
    $add_basic_salary = "ALTER TABLE employees ADD COLUMN basic_salary DECIMAL(10,2) DEFAULT 0";
    if ($conn->query($add_basic_salary)) {
        echo "✅ تم إضافة عمود basic_salary لجدول employees<br>";
    } else {
        echo "❌ خطأ في إضافة عمود basic_salary: " . $conn->error . "<br>";
    }
}

echo "<h3>اختبار الاتصال:</h3>";
$test_query = $conn->query("SELECT 1");
if ($test_query) {
    echo "✅ الاتصال بقاعدة البيانات يعمل بشكل طبيعي<br>";
} else {
    echo "❌ مشكلة في الاتصال بقاعدة البيانات<br>";
}

echo "<br><a href='add_expense.php'>العودة لإضافة المصروفات</a>";
?>
