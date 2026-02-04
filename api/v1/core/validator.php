<?php
/**
 * Validator محترف للتحقق من البيانات
 */

class ApiValidator {
    private $errors = [];
    private $data = [];
    
    public function __construct($data) {
        $this->data = $data;
    }
    
    /**
     * التحقق من حقل مطلوب
     */
    public function required($field, $message = null) {
        if (!isset($this->data[$field]) || $this->data[$field] === '' || $this->data[$field] === null) {
            $this->errors[$field][] = $message ?? "الحقل $field مطلوب";
        }
        return $this;
    }
    
    /**
     * التحقق من نوع البيانات
     */
    public function type($field, $type, $message = null) {
        if (!isset($this->data[$field])) {
            return $this;
        }
        
        $value = $this->data[$field];
        $valid = false;
        
        switch ($type) {
            case 'string':
                $valid = is_string($value);
                break;
            case 'integer':
            case 'int':
                $valid = is_int($value) || (is_numeric($value) && intval($value) == $value);
                break;
            case 'float':
            case 'double':
                $valid = is_float($value) || is_numeric($value);
                break;
            case 'boolean':
            case 'bool':
                $valid = is_bool($value) || in_array($value, [0, 1, '0', '1', true, false], true);
                break;
            case 'array':
                $valid = is_array($value);
                break;
            case 'email':
                $valid = filter_var($value, FILTER_VALIDATE_EMAIL) !== false;
                break;
            case 'url':
                $valid = filter_var($value, FILTER_VALIDATE_URL) !== false;
                break;
            case 'date':
                $valid = strtotime($value) !== false;
                break;
            case 'uuid':
                $valid = preg_match('/^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i', $value);
                break;
        }
        
        if (!$valid) {
            $this->errors[$field][] = $message ?? "الحقل $field يجب أن يكون من نوع $type";
        }
        
        return $this;
    }
    
    /**
     * التحقق من الحد الأدنى
     */
    public function min($field, $min, $message = null) {
        if (!isset($this->data[$field])) {
            return $this;
        }
        
        $value = $this->data[$field];
        
        if (is_string($value)) {
            if (mb_strlen($value) < $min) {
                $this->errors[$field][] = $message ?? "الحقل $field يجب ألا يقل عن $min حرف";
            }
        } elseif (is_numeric($value)) {
            if ($value < $min) {
                $this->errors[$field][] = $message ?? "الحقل $field يجب ألا يقل عن $min";
            }
        }
        
        return $this;
    }
    
    /**
     * التحقق من الحد الأقصى
     */
    public function max($field, $max, $message = null) {
        if (!isset($this->data[$field])) {
            return $this;
        }
        
        $value = $this->data[$field];
        
        if (is_string($value)) {
            if (mb_strlen($value) > $max) {
                $this->errors[$field][] = $message ?? "الحقل $field يجب ألا يزيد عن $max حرف";
            }
        } elseif (is_numeric($value)) {
            if ($value > $max) {
                $this->errors[$field][] = $message ?? "الحقل $field يجب ألا يزيد عن $max";
            }
        }
        
        return $this;
    }
    
    /**
     * التحقق من قيمة ضمن مجموعة
     */
    public function in($field, $values, $message = null) {
        if (!isset($this->data[$field])) {
            return $this;
        }
        
        if (!in_array($this->data[$field], $values, true)) {
            $this->errors[$field][] = $message ?? "الحقل $field يجب أن يكون أحد القيم: " . implode(', ', $values);
        }
        
        return $this;
    }
    
    /**
     * التحقق من تطابق regex
     */
    public function regex($field, $pattern, $message = null) {
        if (!isset($this->data[$field])) {
            return $this;
        }
        
        if (!preg_match($pattern, $this->data[$field])) {
            $this->errors[$field][] = $message ?? "الحقل $field بصيغة غير صحيحة";
        }
        
        return $this;
    }
    
    /**
     * التحقق من رقم هاتف يمني
     */
    public function yemenPhone($field, $message = null) {
        return $this->regex($field, '/^(77|78|73|71|70)[0-9]{7}$/', $message ?? 'رقم الهاتف يجب أن يكون رقم يمني صحيح');
    }
    
    /**
     * التحقق من التفرد في قاعدة البيانات
     */
    public function unique($field, $table, $column, $conn, $excludeId = null, $message = null) {
        if (!isset($this->data[$field])) {
            return $this;
        }
        
        $value = $this->data[$field];
        $sql = "SELECT COUNT(*) as count FROM $table WHERE $column = ?";
        $params = [$value];
        $types = 's';
        
        if ($excludeId) {
            $sql .= " AND id != ?";
            $params[] = $excludeId;
            $types .= 'i';
        }
        
        $stmt = $conn->prepare($sql);
        $stmt->bind_param($types, ...$params);
        $stmt->execute();
        $result = $stmt->get_result()->fetch_assoc();
        
        if ($result['count'] > 0) {
            $this->errors[$field][] = $message ?? "الحقل $field موجود مسبقاً";
        }
        
        return $this;
    }
    
    /**
     * التحقق من وجود مرجع في قاعدة البيانات
     */
    public function exists($field, $table, $column, $conn, $message = null) {
        if (!isset($this->data[$field])) {
            return $this;
        }
        
        $value = $this->data[$field];
        $sql = "SELECT COUNT(*) as count FROM $table WHERE $column = ?";
        
        $stmt = $conn->prepare($sql);
        $stmt->bind_param('s', $value);
        $stmt->execute();
        $result = $stmt->get_result()->fetch_assoc();
        
        if ($result['count'] == 0) {
            $this->errors[$field][] = $message ?? "الحقل $field يشير إلى مرجع غير موجود";
        }
        
        return $this;
    }
    
    /**
     * التحقق من التطابق بين حقلين
     */
    public function match($field, $otherField, $message = null) {
        if (!isset($this->data[$field]) || !isset($this->data[$otherField])) {
            return $this;
        }
        
        if ($this->data[$field] !== $this->data[$otherField]) {
            $this->errors[$field][] = $message ?? "الحقل $field يجب أن يطابق $otherField";
        }
        
        return $this;
    }
    
    /**
     * validation مخصص
     */
    public function custom($field, $callback, $message = null) {
        if (!isset($this->data[$field])) {
            return $this;
        }
        
        $valid = $callback($this->data[$field], $this->data);
        
        if (!$valid) {
            $this->errors[$field][] = $message ?? "الحقل $field غير صالح";
        }
        
        return $this;
    }
    
    /**
     * التحقق من صحة التاريخ
     */
    public function dateFormat($field, $format = 'Y-m-d', $message = null) {
        if (!isset($this->data[$field])) {
            return $this;
        }
        
        $d = DateTime::createFromFormat($format, $this->data[$field]);
        
        if (!$d || $d->format($format) !== $this->data[$field]) {
            $this->errors[$field][] = $message ?? "الحقل $field يجب أن يكون بصيغة $format";
        }
        
        return $this;
    }
    
    /**
     * هل التحقق نجح؟
     */
    public function passes() {
        return empty($this->errors);
    }
    
    /**
     * هل التحقق فشل؟
     */
    public function fails() {
        return !$this->passes();
    }
    
    /**
     * الحصول على الأخطاء
     */
    public function getErrors() {
        return $this->errors;
    }
    
    /**
     * الحصول على أول خطأ
     */
    public function getFirstError() {
        if (empty($this->errors)) {
            return null;
        }
        
        $firstField = array_key_first($this->errors);
        return $this->errors[$firstField][0] ?? null;
    }
    
    /**
     * إرجاع استجابة خطأ إذا فشل التحقق
     */
    public function validate() {
        if ($this->fails()) {
            ApiResponse::error(
                ApiErrorCodes::VALIDATION_REQUIRED_FIELD,
                [
                    'validation_errors' => $this->errors,
                    'first_error' => $this->getFirstError()
                ]
            );
        }
        
        return true;
    }
    
    /**
     * validation سريع
     */
    public static function make($data) {
        return new self($data);
    }
}

/**
 * قواعد Validation مُجهزة مسبقاً للـ entities
 */
class ValidationRules {
    /**
     * قواعد Rooms
     */
    public static function rooms($data, $conn, $isUpdate = false, $id = null) {
        $validator = ApiValidator::make($data);
        
        if (!$isUpdate) {
            $validator->required('room_number')->required('type')->required('price')->required('status');
        }
        
        if (isset($data['room_number'])) {
            $validator->type('room_number', 'string')
                     ->min('room_number', 1)
                     ->max('room_number', 10);
            
            if (!$isUpdate || $id) {
                $validator->unique('room_number', 'rooms', 'room_number', $conn, $id);
            }
        }
        
        if (isset($data['type'])) {
            $validator->type('type', 'string')->in('type', ['standard', 'deluxe', 'suite', 'vip']);
        }
        
        if (isset($data['price'])) {
            $validator->type('price', 'float')->min('price', 0);
        }
        
        if (isset($data['status'])) {
            $validator->in('status', ['شاغرة', 'محجوزة', 'صيانة']);
        }
        
        if (isset($data['cleaning_status'])) {
            $validator->in('cleaning_status', ['clean', 'needs_cleaning', 'in_progress']);
        }
        
        return $validator;
    }
    
    /**
     * قواعد Bookings
     */
    public static function bookings($data, $conn, $isUpdate = false) {
        $validator = ApiValidator::make($data);
        
        if (!$isUpdate) {
            $validator->required('room_number')
                     ->required('guest_name')
                     ->required('guest_phone')
                     ->required('checkin_date')
                     ->required('status');
        }
        
        if (isset($data['room_number'])) {
            $validator->exists('room_number', 'rooms', 'room_number', $conn);
        }
        
        if (isset($data['guest_name'])) {
            $validator->type('guest_name', 'string')->min('guest_name', 2)->max('guest_name', 100);
        }
        
        if (isset($data['guest_phone'])) {
            $validator->type('guest_phone', 'string')->yemenPhone('guest_phone');
        }
        
        if (isset($data['guest_id_type'])) {
            $validator->in('guest_id_type', ['بطاقة شخصية', 'رخصة قيادة', 'جواز سفر']);
        }
        
        if (isset($data['guest_nationality'])) {
            $validator->type('guest_nationality', 'string')->min('guest_nationality', 2);
        }
        
        if (isset($data['checkin_date'])) {
            $validator->type('checkin_date', 'date');
        }
        
        if (isset($data['status'])) {
            $validator->in('status', ['محجوزة', 'شاغرة', 'ملغي']);
        }
        
        if (isset($data['payment_status'])) {
            $validator->in('payment_status', ['pending', 'partial', 'paid', 'refunded']);
        }
        
        if (isset($data['expected_nights'])) {
            $validator->type('expected_nights', 'int')->min('expected_nights', 1);
        }
        
        return $validator;
    }
    
    /**
     * قواعد Employees
     */
    public static function employees($data, $conn, $isUpdate = false) {
        $validator = ApiValidator::make($data);
        
        if (!$isUpdate) {
            $validator->required('name')->required('position')->required('basic_salary');
        }
        
        if (isset($data['name'])) {
            $validator->type('name', 'string')->min('name', 2)->max('name', 100);
        }
        
        if (isset($data['position'])) {
            $validator->type('position', 'string');
        }
        
        if (isset($data['basic_salary'])) {
            $validator->type('basic_salary', 'float')->min('basic_salary', 0);
        }
        
        if (isset($data['phone'])) {
            $validator->yemenPhone('phone');
        }
        
        if (isset($data['status'])) {
            $validator->in('status', ['active', 'inactive', 'suspended']);
        }
        
        return $validator;
    }
    
    /**
     * قواعد Payments
     */
    public static function payments($data, $conn, $isUpdate = false) {
        $validator = ApiValidator::make($data);
        
        if (!$isUpdate) {
            $validator->required('booking_id')->required('amount')->required('payment_method');
        }
        
        if (isset($data['amount'])) {
            $validator->type('amount', 'float')->min('amount', 0);
        }
        
        if (isset($data['payment_method'])) {
            $validator->in('payment_method', ['cash', 'card', 'bank_transfer', 'other']);
        }
        
        if (isset($data['revenue_type'])) {
            $validator->in('revenue_type', ['room', 'service', 'food', 'other']);
        }
        
        return $validator;
    }
}
