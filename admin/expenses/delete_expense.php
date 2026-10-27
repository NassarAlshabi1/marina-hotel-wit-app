<?php
session_start();
require_once '../../includes/db.php';

if (!isset($_SESSION['user_id'])) {
    header("Location: login.php");
    exit();
}

$expense_id = $_GET['id'] ?? 0;

if ($expense_id) {
    try {
        $conn->begin_transaction();
        
        // تسجيل عملية الحذف في السجل أولاً
        $log_query = "INSERT INTO expense_logs 
                     (expense_id, action, details, user_id) 
                     SELECT id, 'delete', CONCAT('تم حذف المصروف: ', description), ? 
                     FROM expenses WHERE id = ?";
        $log_stmt = $conn->prepare($log_query);
        $log_stmt->bind_param("ii", $_SESSION['user_id'], $expense_id);
        $log_stmt->execute();
        
        // ثم حذف المصروف
        $delete_query = "DELETE FROM expenses WHERE id = ?";
        $delete_stmt = $conn->prepare($delete_query);
        $delete_stmt->bind_param("i", $expense_id);
        $delete_stmt->execute();
        
        $conn->commit();
        $_SESSION['success'] = "تم حذف المصروف بنجاح";
    } catch (Exception $e) {
        $conn->rollback();
        $_SESSION['error'] = "خطأ في حذف المصروف: " . $e->getMessage();
    }
} else {
    $_SESSION['error'] = "لم يتم تحديد مصروف للحذف";
}

header("Location: expenses.php");
exit();
?>
