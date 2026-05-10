<?php
// هذا مثال على كيفية تعديل فحص الصلاحيات لاستخدام user_type بدلاً من role

// بدلاً من:
// $user_role = $_SESSION['role'] ?? '';
// if (!in_array($user_role, ['admin', 'finance', 'manager'])) {

// يمكن استخدام:
$user_type = $_SESSION['user_type'] ?? '';
if (!in_array($user_type, ['admin'])) { // أو ['admin', 'employee'] إذا كنت تريد السماح للموظفين
    die('ليس لديك صلاحية للوصول لهذه الصفحة');
}

echo "✅ هذا مثال على الفحص البديل";
?>