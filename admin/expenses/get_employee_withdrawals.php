<?php
session_start();
require_once '../../includes/db.php';

if (!isset($_GET['employee_id']) || empty($_GET['employee_id'])) {
    echo json_encode(['error' => 'معرف الموظف مطلوب']);
    exit;
}

$employee_id = (int)$_GET['employee_id'];

try {
    // جلب بيانات الموظف
    $employee_query = "SELECT basic_salary, name FROM employees WHERE id = ? AND status = 'active'";
    $employee_stmt = $conn->prepare($employee_query);
    $employee_stmt->bind_param("i", $employee_id);
    $employee_stmt->execute();
    $employee_result = $employee_stmt->get_result();
    
    if ($employee_result->num_rows === 0) {
        echo json_encode(['error' => 'الموظف غير موجود']);
        exit;
    }
    
    $employee = $employee_result->fetch_assoc();
    
    // حساب إجمالي المسحوب هذا الشهر
    $withdrawal_query = "SELECT COALESCE(SUM(amount), 0) as total_withdrawn 
                        FROM salary_withdrawals 
                        WHERE employee_id = ? 
                        AND MONTH(date) = MONTH(CURRENT_DATE()) 
                        AND YEAR(date) = YEAR(CURRENT_DATE())";
    $withdrawal_stmt = $conn->prepare($withdrawal_query);
    $withdrawal_stmt->bind_param("i", $employee_id);
    $withdrawal_stmt->execute();
    $withdrawal_result = $withdrawal_stmt->get_result();
    $withdrawal = $withdrawal_result->fetch_assoc();
    
    $response = [
        'employee_name' => $employee['name'],
        'basic_salary' => (float)$employee['basic_salary'],
        'total_withdrawn' => (float)$withdrawal['total_withdrawn'],
        'remaining' => (float)$employee['basic_salary'] - (float)$withdrawal['total_withdrawn']
    ];
    
    echo json_encode($response);
    
} catch (Exception $e) {
    echo json_encode(['error' => 'حدث خطأ في جلب البيانات: ' . $e->getMessage()]);
}
?>
