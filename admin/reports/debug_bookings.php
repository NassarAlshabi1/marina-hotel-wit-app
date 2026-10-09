<?php
require_once '../../includes/db.php';

echo "<h2>فحص بنية جدول bookings</h2>";

// فحص بنية جدول bookings
$query = "DESCRIBE bookings";
$result = $conn->query($query);

if ($result) {
    echo "<h3>أعمدة جدول bookings:</h3>";
    echo "<table border='1' style='border-collapse: collapse; width: 100%;'>";
    echo "<tr><th>اسم العمود</th><th>النوع</th><th>Null</th><th>Key</th><th>Default</th><th>Extra</th></tr>";
    
    while ($row = $result->fetch_assoc()) {
        echo "<tr>";
        echo "<td>" . $row['Field'] . "</td>";
        echo "<td>" . $row['Type'] . "</td>";
        echo "<td>" . $row['Null'] . "</td>";
        echo "<td>" . $row['Key'] . "</td>";
        echo "<td>" . $row['Default'] . "</td>";
        echo "<td>" . $row['Extra'] . "</td>";
        echo "</tr>";
    }
    echo "</table>";
} else {
    echo "خطأ في فحص بنية الجدول: " . $conn->error;
}

// فحص عينة من البيانات
echo "<h3>عينة من بيانات جدول bookings:</h3>";
$sample_query = "SELECT * FROM bookings LIMIT 5";
$sample_result = $conn->query($sample_query);

if ($sample_result && $sample_result->num_rows > 0) {
    echo "<table border='1' style='border-collapse: collapse; width: 100%; font-size: 12px;'>";
    
    // طباعة رؤوس الأعمدة
    $first_row = $sample_result->fetch_assoc();
    echo "<tr>";
    foreach ($first_row as $column => $value) {
        echo "<th>" . $column . "</th>";
    }
    echo "</tr>";
    
    // طباعة الصف الأول
    echo "<tr>";
    foreach ($first_row as $column => $value) {
        echo "<td>" . htmlspecialchars($value ?? 'NULL') . "</td>";
    }
    echo "</tr>";
    
    // طباعة باقي الصفوف
    while ($row = $sample_result->fetch_assoc()) {
        echo "<tr>";
        foreach ($row as $column => $value) {
            echo "<td>" . htmlspecialchars($value ?? 'NULL') . "</td>";
        }
        echo "</tr>";
    }
    echo "</table>";
} else {
    echo "لا توجد بيانات في جدول bookings أو حدث خطأ: " . $conn->error;
}

$conn->close();
?>
