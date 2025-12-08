<?php
require_once 'includes/db.php';

echo "<h2>إصلاح قاعدة البيانات</h2>";

// فحص جدول salary_withdrawals
echo "<h3>فحص جدول salary_withdrawals:</h3>";
$check_table = $conn->query("SHOW TABLES LIKE 'salary_withdrawals'");

if ($check_table->num_rows > 0) {
    echo "✅ الجدول موجود<br>";
    
    // فحص الأعمدة
    echo "<h4>الأعمدة الحالية:</h4>";
    $columns = $conn->query("SHOW COLUMNS FROM salary_withdrawals");
    $existing_columns = [];
    
    echo "<table border='1'>";
    echo "<tr><th>العمود</th><th>النوع</th></tr>";
    while ($col = $columns->fetch_assoc()) {
        $existing_columns[] = $col['Field'];
        echo "<tr><td>{$col['Field']}</td><td>{$col['Type']}</td></tr>";
    }
    echo "</table><br>";
    
    // التحقق من وجود العمود withdrawal_type
    if (!in_array('withdrawal_type', $existing_columns)) {
        echo "❌ العمود withdrawal_type مفقود - سيتم إضافته<br>";
        
        $add_column = "ALTER TABLE salary_withdrawals ADD COLUMN withdrawal_type VARCHAR(50) DEFAULT 'cash'";
        if ($conn->query($add_column)) {
            echo "✅ تم إضافة العمود withdrawal_type بنجاح<br>";
        } else {
            echo "❌ خطأ في إضافة العمود: " . $conn->error . "<br>";
        }
    } else {
        echo "✅ العمود withdrawal_type موجود<br>";
    }
    
} else {
    echo "❌ الجدول غير موجود - سيتم إنشاؤه<br>";
    
    $create_table = "
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
    
    if ($conn->query($create_table)) {
        echo "✅ تم إنشاء جدول salary_withdrawals بنجاح<br>";
    } else {
        echo "❌ خطأ في إنشاء الجدول: " . $conn->error . "<br>";
    }
}

// فحص جدول expenses
echo "<h3>فحص جدول expenses:</h3>";
$check_expenses = $conn->query("SHOW TABLES LIKE 'expenses'");
if ($check_expenses->num_rows == 0) {
    echo "❌ جدول expenses غير موجود - سيتم إنشاؤه<br>";
    
    $create_expenses = "
    CREATE TABLE expenses (
        id INT AUTO_INCREMENT PRIMARY KEY,
        expense_type VARCHAR(50) NOT NULL,
        related_id INT NULL,
        description TEXT,
        amount DECIMAL(10,2) NOT NULL,
        date DATE NOT NULL,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        INDEX idx_expense_type (expense_type),
        INDEX idx_date (date)
    )";
    
    if ($conn->query($create_expenses)) {
        echo "✅ تم إنشاء جدول expenses بنجاح<br>";
    } else {
        echo "❌ خطأ في إنشاء جدول expenses: " . $conn->error . "<br>";
    }
} else {
    echo "✅ جدول expenses موجود<br>";
}

echo "<br><h3>اختبار الإدراج:</h3>";

// اختبار إدراج بسيط
$test_insert = "INSERT INTO salary_withdrawals (employee_id, amount, date, notes, withdrawal_type) 
                VALUES (1, 100.00, CURDATE(), 'اختبار', 'cash')";

if ($conn->query($test_insert)) {
    echo "✅ اختبار الإدراج نجح<br>";
    
    // حذف البيان التجريبي
    $conn->query("DELETE FROM salary_withdrawals WHERE notes = 'اختبار'");
    echo "✅ تم حذف البيان التجريبي<br>";
} else {
    echo "❌ خطأ في اختبار الإدراج: " . $conn->error . "<br>";
}

echo "<br><a href='admin/expenses/add_expense.php'>جرب إضافة مصروف الآن</a>";
?><?php
require_once 'includes/db.php';

echo "<h2>إصلاح قاعدة البيانات</h2>";

// فحص جدول salary_withdrawals
echo "<h3>فحص جدول salary_withdrawals:</h3>";
$check_table = $conn->query("SHOW TABLES LIKE 'salary_withdrawals'");

if ($check_table->num_rows > 0) {
    echo "✅ الجدول موجود<br>";
    
    // فحص الأعمدة
    echo "<h4>الأعمدة الحالية:</h4>";
    $columns = $conn->query("SHOW COLUMNS FROM salary_withdrawals");
    $existing_columns = [];
    
    echo "<table border='1'>";
    echo "<tr><th>العمود</th><th>النوع</th></tr>";
    while ($col = $columns->fetch_assoc()) {
        $existing_columns[] = $col['Field'];
        echo "<tr><td>{$col['Field']}</td><td>{$col['Type']}</td></tr>";
    }
    echo "</table><br>";
    
    // التحقق من وجود العمود withdrawal_type
    if (!in_array('withdrawal_type', $existing_columns)) {
        echo "❌ العمود withdrawal_type مفقود - سيتم إضافته<br>";
        
        $add_column = "ALTER TABLE salary_withdrawals ADD COLUMN withdrawal_type VARCHAR(50) DEFAULT 'cash'";
        if ($conn->query($add_column)) {
            echo "✅ تم إضافة العمود withdrawal_type بنجاح<br>";
        } else {
            echo "❌ خطأ في إضافة العمود: " . $conn->error . "<br>";
        }
    } else {
        echo "✅ العمود withdrawal_type موجود<br>";
    }
    
} else {
    echo "❌ الجدول غير موجود - سيتم إنشاؤه<br>";
    
    $create_table = "
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
    
    if ($conn->query($create_table)) {
        echo "✅ تم إنشاء جدول salary_withdrawals بنجاح<br>";
    } else {
        echo "❌ خطأ في إنشاء الجدول: " . $conn->error . "<br>";
    }
}

// فحص جدول expenses
echo "<h3>فحص جدول expenses:</h3>";
$check_expenses = $conn->query("SHOW TABLES LIKE 'expenses'");
if ($check_expenses->num_rows == 0) {
    echo "❌ جدول expenses غير موجود - سيتم إنشاؤه<br>";
    
    $create_expenses = "
    CREATE TABLE expenses (
        id INT AUTO_INCREMENT PRIMARY KEY,
        expense_type VARCHAR(50) NOT NULL,
        related_id INT NULL,
        description TEXT,
        amount DECIMAL(10,2) NOT NULL,
        date DATE NOT NULL,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        INDEX idx_expense_type (expense_type),
        INDEX idx_date (date)
    )";
    
    if ($conn->query($create_expenses)) {
        echo "✅ تم إنشاء جدول expenses بنجاح<br>";
    } else {
        echo "❌ خطأ في إنشاء جدول expenses: " . $conn->error . "<br>";
    }
} else {
    echo "✅ جدول expenses موجود<br>";
}

echo "<br><h3>اختبار الإدراج:</h3>";

// اختبار إدراج بسيط
$test_insert = "INSERT INTO salary_withdrawals (employee_id, amount, date, notes, withdrawal_type) 
                VALUES (1, 100.00, CURDATE(), 'اختبار', 'cash')";

if ($conn->query($test_insert)) {
    echo "✅ اختبار الإدراج نجح<br>";
    
    // حذف البيان التجريبي
    $conn->query("DELETE FROM salary_withdrawals WHERE notes = 'اختبار'");
    echo "✅ تم حذف البيان التجريبي<br>";
} else {
    echo "❌ خطأ في اختبار الإدراج: " . $conn->error . "<br>";
}

echo "<br><a href='admin/expenses/add_expense.php'>جرب إضافة مصروف الآن</a>";
?>