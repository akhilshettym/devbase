-- ============================================================================
-- MYSQL MASTERY LAB DATABASE
-- Target: MySQL 8.x / MySQL 8.4
-- Domain: Enterprise ERP / Employee + Projects + Customers + Orders
--
-- HOW TO USE
-- 1) Run this file from top to bottom in MySQL Workbench or the mysql CLI.
-- 2) Do not skip sections while learning; later sections intentionally build
--    on objects and data created earlier.
-- 3) Statements marked OPTIONAL / ADMIN may require extra privileges or a
--    server configuration change. The core learning path remains runnable
--    without them.
--
-- LEARNING PATH
--   00  Reset + create database
--   01  DDL: database, tables, constraints, ALTER
--   02  Seed realistic data
--   03  Metadata / inspection
--   04  INSERT / UPDATE / DELETE / REPLACE / INSERT...SELECT
--   05  SELECT fundamentals + operators + NULL + CASE
--   06  Functions: string / numeric / date-time / conditional / JSON
--   07  Aggregation: GROUP BY / HAVING / ROLLUP
--   08  Joins: INNER / LEFT / RIGHT / CROSS / SELF / anti-joins
--   09  Set operations: UNION / INTERSECT / EXCEPT
--   10  Subqueries: scalar / IN / EXISTS / correlated / derived
--   11  CTEs + recursive CTEs
--   12  Window functions + analytics
--   13  Views
--   14  Temporary tables + CREATE TABLE ... SELECT
--   15  Transactions / SAVEPOINT / locking / isolation
--   16  Stored procedures + function
--   17  Triggers + audit trail
--   18  Events (server scheduler required to execute)
--   19  Prepared statements
--   20  Indexes + EXPLAIN + ANALYZE
--   21  Advanced DML patterns
--   22  Data quality / constraint labs
--   23  Optional administration: users / roles / grants
--   24  Capstone challenge queries
--   25  Cleanup lab
-- ============================================================================

-- ============================================================================
-- 00. RESET THE TRAINING ENVIRONMENT
-- ============================================================================

-- WARNING: This deletes the training database if it already exists.
DROP DATABASE IF EXISTS mysql_mastery_lab;

CREATE DATABASE mysql_mastery_lab
    CHARACTER SET utf8mb4
    COLLATE utf8mb4_0900_ai_ci;

USE mysql_mastery_lab;

-- Confirm the active database.
SELECT DATABASE() AS active_database;

-- ============================================================================
-- 01. DDL: CREATE TABLES, DATA TYPES, KEYS, CONSTRAINTS
-- ============================================================================

-- Reference table: company departments.
CREATE TABLE departments (
    department_id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    department_code VARCHAR(20) NOT NULL UNIQUE,
    department_name VARCHAR(100) NOT NULL UNIQUE,
    budget DECIMAL(14,2) NOT NULL DEFAULT 0.00,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT chk_department_budget CHECK (budget >= 0)
) ENGINE=InnoDB;

-- Physical office locations.
CREATE TABLE locations (
    location_id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    location_name VARCHAR(100) NOT NULL,
    city VARCHAR(100) NOT NULL,
    state_province VARCHAR(100) NULL,
    country_code CHAR(2) NOT NULL,
    postal_code VARCHAR(20) NULL,
    UNIQUE KEY uq_location (location_name, city, country_code)
) ENGINE=InnoDB;

-- Core employee table.
-- manager_id is a self-referencing foreign key, giving us an employee hierarchy.
CREATE TABLE employees (
    employee_id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    employee_code VARCHAR(20) NOT NULL UNIQUE,
    first_name VARCHAR(60) NOT NULL,
    last_name VARCHAR(60) NOT NULL,
    email VARCHAR(255) NOT NULL UNIQUE,
    phone VARCHAR(30) NULL,
    department_id INT UNSIGNED NOT NULL,
    location_id INT UNSIGNED NOT NULL,
    manager_id INT UNSIGNED NULL,
    job_title VARCHAR(120) NOT NULL,
    employment_type ENUM('FULL_TIME','PART_TIME','CONTRACT','INTERN') NOT NULL DEFAULT 'FULL_TIME',
    hire_date DATE NOT NULL,
    birth_date DATE NULL,
    current_salary DECIMAL(12,2) NOT NULL,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    profile JSON NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    CONSTRAINT fk_employee_department
        FOREIGN KEY (department_id) REFERENCES departments(department_id),
    CONSTRAINT fk_employee_location
        FOREIGN KEY (location_id) REFERENCES locations(location_id),
    CONSTRAINT fk_employee_manager
        FOREIGN KEY (manager_id) REFERENCES employees(employee_id)
        ON DELETE SET NULL,
    CONSTRAINT chk_employee_salary CHECK (current_salary >= 0),
    CONSTRAINT chk_employee_dates CHECK (birth_date IS NULL OR birth_date < hire_date)
) ENGINE=InnoDB;

-- One-to-one employee emergency/contact information table.
CREATE TABLE employee_contacts (
    employee_id INT UNSIGNED PRIMARY KEY,
    contact_name VARCHAR(120) NOT NULL,
    relationship VARCHAR(60) NOT NULL,
    contact_phone VARCHAR(30) NOT NULL,
    contact_email VARCHAR(255) NULL,
    CONSTRAINT fk_contact_employee
        FOREIGN KEY (employee_id) REFERENCES employees(employee_id)
        ON DELETE CASCADE
) ENGINE=InnoDB;

-- One employee can have many historical salary rows.
CREATE TABLE salary_history (
    salary_history_id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    employee_id INT UNSIGNED NOT NULL,
    effective_from DATE NOT NULL,
    effective_to DATE NULL,
    salary DECIMAL(12,2) NOT NULL,
    change_reason VARCHAR(255) NOT NULL,
    CONSTRAINT fk_salary_employee
        FOREIGN KEY (employee_id) REFERENCES employees(employee_id)
        ON DELETE CASCADE,
    CONSTRAINT chk_salary_value CHECK (salary >= 0),
    CONSTRAINT chk_salary_dates CHECK (effective_to IS NULL OR effective_to >= effective_from),
    UNIQUE KEY uq_salary_period (employee_id, effective_from)
) ENGINE=InnoDB;

-- Skills demonstrate a many-to-many relationship through employee_skills.
CREATE TABLE skills (
    skill_id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    skill_name VARCHAR(100) NOT NULL UNIQUE,
    skill_category VARCHAR(100) NOT NULL
) ENGINE=InnoDB;

CREATE TABLE employee_skills (
    employee_id INT UNSIGNED NOT NULL,
    skill_id INT UNSIGNED NOT NULL,
    proficiency TINYINT UNSIGNED NOT NULL,
    years_experience DECIMAL(4,1) NOT NULL DEFAULT 0.0,
    PRIMARY KEY (employee_id, skill_id),
    CONSTRAINT fk_employee_skill_employee
        FOREIGN KEY (employee_id) REFERENCES employees(employee_id)
        ON DELETE CASCADE,
    CONSTRAINT fk_employee_skill_skill
        FOREIGN KEY (skill_id) REFERENCES skills(skill_id)
        ON DELETE CASCADE,
    CONSTRAINT chk_skill_proficiency CHECK (proficiency BETWEEN 1 AND 5),
    CONSTRAINT chk_skill_years CHECK (years_experience >= 0)
) ENGINE=InnoDB;

-- Clients that fund projects.
CREATE TABLE clients (
    client_id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    client_name VARCHAR(150) NOT NULL UNIQUE,
    industry VARCHAR(100) NOT NULL,
    city VARCHAR(100) NOT NULL,
    country_code CHAR(2) NOT NULL,
    account_manager_id INT UNSIGNED NULL,
    credit_limit DECIMAL(14,2) NOT NULL DEFAULT 0.00,
    metadata JSON NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_client_account_manager
        FOREIGN KEY (account_manager_id) REFERENCES employees(employee_id)
        ON DELETE SET NULL,
    CONSTRAINT chk_client_credit CHECK (credit_limit >= 0)
) ENGINE=InnoDB;

-- Projects demonstrate another relationship between employees and clients.
CREATE TABLE projects (
    project_id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    project_code VARCHAR(30) NOT NULL UNIQUE,
    project_name VARCHAR(150) NOT NULL,
    client_id INT UNSIGNED NOT NULL,
    department_id INT UNSIGNED NOT NULL,
    project_manager_id INT UNSIGNED NOT NULL,
    status ENUM('PLANNED','ACTIVE','ON_HOLD','COMPLETED','CANCELLED') NOT NULL DEFAULT 'PLANNED',
    start_date DATE NOT NULL,
    end_date DATE NULL,
    budget DECIMAL(14,2) NOT NULL DEFAULT 0.00,
    tags JSON NULL,
    CONSTRAINT fk_project_client
        FOREIGN KEY (client_id) REFERENCES clients(client_id),
    CONSTRAINT fk_project_department
        FOREIGN KEY (department_id) REFERENCES departments(department_id),
    CONSTRAINT fk_project_manager
        FOREIGN KEY (project_manager_id) REFERENCES employees(employee_id),
    CONSTRAINT chk_project_dates CHECK (end_date IS NULL OR end_date >= start_date),
    CONSTRAINT chk_project_budget CHECK (budget >= 0)
) ENGINE=InnoDB;

-- Many-to-many: employees can work on many projects and each project has many employees.
CREATE TABLE employee_projects (
    employee_id INT UNSIGNED NOT NULL,
    project_id INT UNSIGNED NOT NULL,
    role_name VARCHAR(100) NOT NULL,
    allocation_percent DECIMAL(5,2) NOT NULL DEFAULT 100.00,
    assigned_on DATE NOT NULL,
    PRIMARY KEY (employee_id, project_id),
    CONSTRAINT fk_ep_employee
        FOREIGN KEY (employee_id) REFERENCES employees(employee_id)
        ON DELETE CASCADE,
    CONSTRAINT fk_ep_project
        FOREIGN KEY (project_id) REFERENCES projects(project_id)
        ON DELETE CASCADE,
    CONSTRAINT chk_ep_allocation CHECK (allocation_percent BETWEEN 0 AND 100)
) ENGINE=InnoDB;

-- Product catalog.
CREATE TABLE products (
    product_id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    sku VARCHAR(40) NOT NULL UNIQUE,
    product_name VARCHAR(150) NOT NULL,
    category VARCHAR(100) NOT NULL,
    unit_price DECIMAL(12,2) NOT NULL,
    cost_price DECIMAL(12,2) NOT NULL,
    stock_reorder_level INT NOT NULL DEFAULT 10,
    attributes JSON NULL,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT chk_product_prices CHECK (unit_price >= 0 AND cost_price >= 0),
    CONSTRAINT chk_product_margin CHECK (unit_price >= cost_price),
    CONSTRAINT chk_reorder_level CHECK (stock_reorder_level >= 0)
) ENGINE=InnoDB;

CREATE TABLE suppliers (
    supplier_id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    supplier_name VARCHAR(150) NOT NULL UNIQUE,
    contact_email VARCHAR(255) NULL,
    country_code CHAR(2) NOT NULL,
    rating DECIMAL(3,2) NOT NULL DEFAULT 0.00,
    metadata JSON NULL,
    CONSTRAINT chk_supplier_rating CHECK (rating BETWEEN 0 AND 5)
) ENGINE=InnoDB;

-- Many-to-many products <-> suppliers.
CREATE TABLE product_suppliers (
    product_id INT UNSIGNED NOT NULL,
    supplier_id INT UNSIGNED NOT NULL,
    supplier_sku VARCHAR(50) NULL,
    lead_time_days INT UNSIGNED NOT NULL DEFAULT 0,
    last_cost DECIMAL(12,2) NULL,
    PRIMARY KEY (product_id, supplier_id),
    CONSTRAINT fk_ps_product
        FOREIGN KEY (product_id) REFERENCES products(product_id)
        ON DELETE CASCADE,
    CONSTRAINT fk_ps_supplier
        FOREIGN KEY (supplier_id) REFERENCES suppliers(supplier_id)
        ON DELETE CASCADE
) ENGINE=InnoDB;

CREATE TABLE warehouses (
    warehouse_id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    warehouse_code VARCHAR(20) NOT NULL UNIQUE,
    warehouse_name VARCHAR(100) NOT NULL,
    city VARCHAR(100) NOT NULL,
    country_code CHAR(2) NOT NULL
) ENGINE=InnoDB;

-- Current inventory snapshot by warehouse/product.
CREATE TABLE inventory (
    warehouse_id INT UNSIGNED NOT NULL,
    product_id INT UNSIGNED NOT NULL,
    quantity INT NOT NULL DEFAULT 0,
    reserved_quantity INT NOT NULL DEFAULT 0,
    last_counted_at DATETIME NULL,
    PRIMARY KEY (warehouse_id, product_id),
    CONSTRAINT fk_inventory_warehouse
        FOREIGN KEY (warehouse_id) REFERENCES warehouses(warehouse_id)
        ON DELETE CASCADE,
    CONSTRAINT fk_inventory_product
        FOREIGN KEY (product_id) REFERENCES products(product_id)
        ON DELETE CASCADE,
    CONSTRAINT chk_inventory_quantity CHECK (quantity >= 0),
    CONSTRAINT chk_inventory_reserved CHECK (reserved_quantity >= 0 AND reserved_quantity <= quantity)
) ENGINE=InnoDB;

-- Customers place orders.
CREATE TABLE customers (
    customer_id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    customer_code VARCHAR(30) NOT NULL UNIQUE,
    first_name VARCHAR(60) NOT NULL,
    last_name VARCHAR(60) NOT NULL,
    email VARCHAR(255) NOT NULL UNIQUE,
    phone VARCHAR(30) NULL,
    city VARCHAR(100) NOT NULL,
    country_code CHAR(2) NOT NULL,
    loyalty_tier ENUM('STANDARD','SILVER','GOLD','PLATINUM') NOT NULL DEFAULT 'STANDARD',
    preferences JSON NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB;

CREATE TABLE orders (
    order_id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    order_number VARCHAR(30) NOT NULL UNIQUE,
    customer_id INT UNSIGNED NOT NULL,
    sales_employee_id INT UNSIGNED NULL,
    order_date DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    status ENUM('PENDING','PAID','SHIPPED','COMPLETED','CANCELLED') NOT NULL DEFAULT 'PENDING',
    shipping_city VARCHAR(100) NOT NULL,
    shipping_country_code CHAR(2) NOT NULL,
    subtotal DECIMAL(14,2) NOT NULL DEFAULT 0.00,
    discount_amount DECIMAL(14,2) NOT NULL DEFAULT 0.00,
    tax_amount DECIMAL(14,2) NOT NULL DEFAULT 0.00,
    total_amount DECIMAL(14,2) NOT NULL DEFAULT 0.00,
    notes TEXT NULL,
    CONSTRAINT fk_order_customer
        FOREIGN KEY (customer_id) REFERENCES customers(customer_id),
    CONSTRAINT fk_order_sales_employee
        FOREIGN KEY (sales_employee_id) REFERENCES employees(employee_id)
        ON DELETE SET NULL,
    CONSTRAINT chk_order_amounts CHECK (
        subtotal >= 0 AND discount_amount >= 0 AND tax_amount >= 0 AND total_amount >= 0
    )
) ENGINE=InnoDB;

-- Line items use a generated column to practice computed/generated data.
CREATE TABLE order_items (
    order_item_id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    order_id BIGINT UNSIGNED NOT NULL,
    product_id INT UNSIGNED NOT NULL,
    quantity INT UNSIGNED NOT NULL,
    unit_price DECIMAL(12,2) NOT NULL,
    discount_percent DECIMAL(5,2) NOT NULL DEFAULT 0.00,
    line_total DECIMAL(14,2)
        GENERATED ALWAYS AS (
            quantity * unit_price * (1 - discount_percent / 100)
        ) STORED,
    CONSTRAINT fk_order_item_order
        FOREIGN KEY (order_id) REFERENCES orders(order_id)
        ON DELETE CASCADE,
    CONSTRAINT fk_order_item_product
        FOREIGN KEY (product_id) REFERENCES products(product_id),
    CONSTRAINT chk_order_item_quantity CHECK (quantity > 0),
    CONSTRAINT chk_order_item_price CHECK (unit_price >= 0),
    CONSTRAINT chk_order_item_discount CHECK (discount_percent BETWEEN 0 AND 100),
    UNIQUE KEY uq_order_product (order_id, product_id)
) ENGINE=InnoDB;

CREATE TABLE payments (
    payment_id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    order_id BIGINT UNSIGNED NOT NULL,
    payment_date DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    amount DECIMAL(14,2) NOT NULL,
    payment_method ENUM('CARD','BANK_TRANSFER','CASH','UPI','WALLET') NOT NULL,
    payment_status ENUM('PENDING','SUCCESS','FAILED','REFUNDED') NOT NULL DEFAULT 'PENDING',
    transaction_reference VARCHAR(100) NULL UNIQUE,
    CONSTRAINT fk_payment_order
        FOREIGN KEY (order_id) REFERENCES orders(order_id)
        ON DELETE CASCADE,
    CONSTRAINT chk_payment_amount CHECK (amount > 0)
) ENGINE=InnoDB;

CREATE TABLE timesheets (
    timesheet_id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    employee_id INT UNSIGNED NOT NULL,
    project_id INT UNSIGNED NOT NULL,
    work_date DATE NOT NULL,
    hours DECIMAL(5,2) NOT NULL,
    billable BOOLEAN NOT NULL DEFAULT TRUE,
    description VARCHAR(255) NULL,
    CONSTRAINT fk_timesheet_employee
        FOREIGN KEY (employee_id) REFERENCES employees(employee_id)
        ON DELETE CASCADE,
    CONSTRAINT fk_timesheet_project
        FOREIGN KEY (project_id) REFERENCES projects(project_id)
        ON DELETE CASCADE,
    CONSTRAINT chk_timesheet_hours CHECK (hours > 0 AND hours <= 24),
    UNIQUE KEY uq_timesheet_entry (employee_id, project_id, work_date)
) ENGINE=InnoDB;

CREATE TABLE expenses (
    expense_id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    employee_id INT UNSIGNED NOT NULL,
    project_id INT UNSIGNED NULL,
    expense_date DATE NOT NULL,
    category VARCHAR(100) NOT NULL,
    amount DECIMAL(12,2) NOT NULL,
    description VARCHAR(255) NOT NULL,
    status ENUM('SUBMITTED','APPROVED','REJECTED','PAID') NOT NULL DEFAULT 'SUBMITTED',
    metadata JSON NULL,
    CONSTRAINT fk_expense_employee
        FOREIGN KEY (employee_id) REFERENCES employees(employee_id)
        ON DELETE CASCADE,
    CONSTRAINT fk_expense_project
        FOREIGN KEY (project_id) REFERENCES projects(project_id)
        ON DELETE SET NULL,
    CONSTRAINT chk_expense_amount CHECK (amount > 0)
) ENGINE=InnoDB;

CREATE TABLE payroll_records (
    payroll_id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    employee_id INT UNSIGNED NOT NULL,
    payroll_month DATE NOT NULL,
    gross_salary DECIMAL(12,2) NOT NULL,
    tax_amount DECIMAL(12,2) NOT NULL DEFAULT 0.00,
    net_salary DECIMAL(12,2) NOT NULL,
    processed_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UNIQUE KEY uq_employee_payroll_month (employee_id, payroll_month),
    CONSTRAINT fk_payroll_employee
        FOREIGN KEY (employee_id) REFERENCES employees(employee_id)
        ON DELETE CASCADE,
    CONSTRAINT chk_payroll_values CHECK (gross_salary >= 0 AND tax_amount >= 0 AND net_salary >= 0)
) ENGINE=InnoDB;

-- Simple audit table used later by a trigger.
CREATE TABLE employee_audit (
    audit_id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    employee_id INT UNSIGNED NOT NULL,
    action_type VARCHAR(50) NOT NULL,
    old_salary DECIMAL(12,2) NULL,
    new_salary DECIMAL(12,2) NULL,
    changed_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    details JSON NULL
) ENGINE=InnoDB;

-- ============================================================================
-- 01B. DDL ALTER TABLE / RENAME / TEMPORARY OBJECT PRACTICE
-- ============================================================================

-- Add a column after the initial CREATE TABLE to practice ALTER TABLE.
ALTER TABLE departments
    ADD COLUMN is_active BOOLEAN NOT NULL DEFAULT TRUE AFTER budget;

-- Add a useful index using ALTER TABLE syntax.
ALTER TABLE employees
    ADD INDEX idx_employee_department_status (department_id, is_active);

-- Demonstrate column modification; keep the definition compatible with seed data.
ALTER TABLE customers
    MODIFY COLUMN phone VARCHAR(40) NULL;

-- Demonstrate a table rename on a throwaway table so it does not disturb the lab.
CREATE TABLE ddl_rename_demo (
    id INT PRIMARY KEY,
    note VARCHAR(100)
);
ALTER TABLE ddl_rename_demo RENAME TO ddl_rename_demo_renamed;
DROP TABLE ddl_rename_demo_renamed;

-- ============================================================================
-- 02. SEED REALISTIC DATA
-- ============================================================================

-- Departments.
INSERT INTO departments (department_code, department_name, budget) VALUES
('ENG', 'Engineering', 1500000.00),
('HR', 'Human Resources', 500000.00),
('FIN', 'Finance', 700000.00),
('SALES', 'Sales', 900000.00),
('OPS', 'Operations', 1100000.00),
('DATA', 'Data & Analytics', 850000.00);

-- Office locations.
INSERT INTO locations (location_name, city, state_province, country_code, postal_code) VALUES
('Mumbai HQ', 'Mumbai', 'Maharashtra', 'IN', '400001'),
('Bengaluru Tech Park', 'Bengaluru', 'Karnataka', 'IN', '560001'),
('London Office', 'London', NULL, 'GB', 'EC1A 1AA'),
('New York Office', 'New York', 'New York', 'US', '10001'),
('Singapore Office', 'Singapore', NULL, 'SG', '048616');

-- Skills.
INSERT INTO skills (skill_name, skill_category) VALUES
('SQL', 'Data'),
('Python', 'Programming'),
('Java', 'Programming'),
('JavaScript', 'Programming'),
('AWS', 'Cloud'),
('Docker', 'DevOps'),
('Project Management', 'Management'),
('Data Visualization', 'Data'),
('Financial Analysis', 'Finance'),
('Recruiting', 'HR');

-- Employees are inserted in manager order so manager IDs are available.
INSERT INTO employees
(employee_code, first_name, last_name, email, phone, department_id, location_id, manager_id,
 job_title, employment_type, hire_date, birth_date, current_salary, profile)
VALUES
('E001', 'Aarav', 'Shah', 'aarav.shah@example.com', '+91-9000000001', 1, 1, NULL,
 'VP of Engineering', 'FULL_TIME', '2017-02-15', '1985-07-10', 180000.00,
 '{"remote": true, "languages": ["English", "Hindi"]}'),
('E002', 'Maya', 'Rao', 'maya.rao@example.com', '+91-9000000002', 4, 1, NULL,
 'Sales Director', 'FULL_TIME', '2018-06-11', '1983-03-22', 165000.00,
 '{"remote": false, "region": "APAC"}'),
('E003', 'Kabir', 'Mehta', 'kabir.mehta@example.com', '+91-9000000003', 2, 1, NULL,
 'HR Director', 'FULL_TIME', '2019-01-07', '1982-09-12', 140000.00,
 '{"remote": true, "specialties": ["benefits", "recruiting"]}'),
('E004', 'Sana', 'Kapoor', 'sana.kapoor@example.com', '+91-9000000004', 3, 1, NULL,
 'Finance Director', 'FULL_TIME', '2018-11-05', '1981-01-30', 150000.00,
 '{"remote": false, "certifications": ["CPA"]}'),
('E005', 'Rohan', 'Patel', 'rohan.patel@example.com', '+91-9000000005', 1, 2, 1,
 'Engineering Manager', 'FULL_TIME', '2020-03-16', '1990-05-14', 125000.00,
 '{"remote": true, "languages": ["English", "Gujarati"]}'),
('E006', 'Isha', 'Nair', 'isha.nair@example.com', '+91-9000000006', 1, 2, 5,
 'Senior Software Engineer', 'FULL_TIME', '2021-07-12', '1993-10-09', 98000.00,
 '{"remote": true, "languages": ["English", "Malayalam"]}'),
('E007', 'Vikram', 'Joshi', 'vikram.joshi@example.com', '+91-9000000007', 6, 2, 1,
 'Data Engineering Manager', 'FULL_TIME', '2020-08-24', '1989-12-19', 130000.00,
 '{"remote": true, "tools": ["dbt", "Airflow"]}'),
('E008', 'Neha', 'Menon', 'neha.menon@example.com', '+91-9000000008', 6, 2, 7,
 'Data Analyst', 'FULL_TIME', '2022-01-17', '1996-04-25', 72000.00,
 '{"remote": true, "tools": ["Tableau", "SQL"]}'),
('E009', 'Omar', 'Khan', 'omar.khan@example.com', '+44-7000000009', 4, 3, 2,
 'Account Executive', 'FULL_TIME', '2021-10-04', '1991-06-03', 85000.00,
 '{"remote": false, "region": "EMEA"}'),
('E010', 'Emily', 'Brown', 'emily.brown@example.com', '+1-7000000010', 4, 4, 2,
 'Account Executive', 'FULL_TIME', '2022-05-23', '1994-11-18', 82000.00,
 '{"remote": true, "region": "AMER"}'),
('E011', 'Liam', 'Tan', 'liam.tan@example.com', '+65-7000000011', 5, 5, NULL,
 'Operations Director', 'FULL_TIME', '2019-09-09', '1984-08-21', 145000.00,
 '{"remote": false, "shift": "day"}'),
('E012', 'Priya', 'Desai', 'priya.desai@example.com', '+91-9000000012', 5, 1, 11,
 'Operations Analyst', 'FULL_TIME', '2023-02-13', '1997-02-07', 68000.00,
 '{"remote": true, "shift": "day"}'),
('E013', 'Arjun', 'Kulkarni', 'arjun.kulkarni@example.com', '+91-9000000013', 1, 1, 5,
 'Software Engineer', 'FULL_TIME', '2024-01-08', '1998-09-03', 70000.00,
 '{"remote": true, "stack": ["Node.js", "MySQL"]}'),
('E014', 'Zoya', 'Ali', 'zoya.ali@example.com', '+91-9000000014', 2, 1, 3,
 'Recruiter', 'FULL_TIME', '2024-04-15', '1999-01-11', 62000.00,
 '{"remote": false, "languages": ["English", "Hindi"]}'),
('E015', 'Daniel', 'Wong', 'daniel.wong@example.com', '+65-7000000015', 3, 5, 4,
 'Financial Analyst', 'FULL_TIME', '2023-08-21', '1996-12-02', 76000.00,
 '{"remote": true, "tools": ["Excel", "SQL"]}');

-- Employee emergency contacts; demonstrates a 1-to-1 relationship.
INSERT INTO employee_contacts (employee_id, contact_name, relationship, contact_phone, contact_email) VALUES
(1, 'Nisha Shah', 'Spouse', '+91-9111110001', 'nisha.shah@example.com'),
(2, 'Raj Rao', 'Spouse', '+91-9111110002', 'raj.rao@example.com'),
(3, 'Anita Mehta', 'Parent', '+91-9111110003', 'anita.mehta@example.com'),
(5, 'Kiran Patel', 'Sibling', '+91-9111110005', 'kiran.patel@example.com'),
(6, 'Dev Nair', 'Parent', '+91-9111110006', 'dev.nair@example.com');

-- Salary history.
INSERT INTO salary_history (employee_id, effective_from, effective_to, salary, change_reason) VALUES
(1, '2017-02-15', '2020-01-31', 140000.00, 'Initial salary'),
(1, '2020-02-01', '2023-06-30', 160000.00, 'Promotion'),
(1, '2023-07-01', NULL, 180000.00, 'Annual review'),
(5, '2020-03-16', '2022-03-31', 100000.00, 'Initial salary'),
(5, '2022-04-01', '2024-03-31', 115000.00, 'Promotion'),
(5, '2024-04-01', NULL, 125000.00, 'Annual review'),
(6, '2021-07-12', '2023-06-30', 85000.00, 'Initial salary'),
(6, '2023-07-01', NULL, 98000.00, 'Promotion'),
(9, '2021-10-04', NULL, 85000.00, 'Initial salary'),
(10, '2022-05-23', NULL, 82000.00, 'Initial salary');

-- Employee skills.
INSERT INTO employee_skills (employee_id, skill_id, proficiency, years_experience) VALUES
(1, 7, 5, 12.0), (1, 1, 4, 8.0),
(5, 1, 5, 8.0), (5, 4, 5, 10.0), (5, 6, 4, 6.0),
(6, 4, 5, 5.0), (6, 1, 5, 4.0), (6, 6, 4, 4.0),
(7, 1, 5, 7.0), (7, 2, 4, 8.0), (7, 5, 4, 6.0),
(8, 1, 5, 3.0), (8, 8, 5, 3.0),
(9, 7, 4, 7.0),
(10, 7, 4, 6.0), (10, 1, 3, 2.0),
(12, 1, 4, 2.0),
(13, 4, 4, 2.0), (13, 1, 4, 2.0),
(14, 10, 5, 2.0),
(15, 9, 4, 3.0), (15, 1, 3, 2.0);

-- Clients.
INSERT INTO clients (client_name, industry, city, country_code, account_manager_id, credit_limit, metadata) VALUES
('Atlas Retail Group', 'Retail', 'Mumbai', 'IN', 9, 2500000.00, '{"priority": "high", "contract_type": "enterprise"}'),
('BlueSky Airlines', 'Aviation', 'Singapore', 'SG', 10, 1800000.00, '{"priority": "medium", "contract_type": "annual"}'),
('Cedar Health Systems', 'Healthcare', 'London', 'GB', 9, 3200000.00, '{"priority": "high", "compliance": true}'),
('Delta Manufacturing', 'Manufacturing', 'New York', 'US', 10, 2100000.00, '{"priority": "medium", "plants": 5}'),
('Evergreen Education', 'Education', 'Bengaluru', 'IN', 9, 900000.00, '{"priority": "low", "contract_type": "annual"}'),
('Futura Media', 'Media', 'Mumbai', 'IN', 10, 1200000.00, '{"priority": "medium", "contract_type": "project"}');

-- Projects.
INSERT INTO projects
(project_code, project_name, client_id, department_id, project_manager_id, status, start_date, end_date, budget, tags)
VALUES
('P1001', 'Retail Data Platform', 1, 6, 7, 'ACTIVE', '2025-01-15', NULL, 450000.00, '["data", "cloud", "analytics"]'),
('P1002', 'Mobile Commerce App', 1, 1, 5, 'ACTIVE', '2025-03-01', NULL, 600000.00, '["mobile", "api", "commerce"]'),
('P1003', 'Airline CRM Upgrade', 2, 1, 5, 'COMPLETED', '2024-02-01', '2025-05-30', 350000.00, '["crm", "integration"]'),
('P1004', 'Healthcare Reporting', 3, 6, 7, 'ACTIVE', '2025-06-15', NULL, 520000.00, '["bi", "compliance", "reporting"]'),
('P1005', 'Factory IoT Rollout', 4, 1, 5, 'ON_HOLD', '2025-08-01', NULL, 800000.00, '["iot", "edge", "cloud"]'),
('P1006', 'Education Portal', 5, 1, 5, 'PLANNED', '2026-01-10', NULL, 250000.00, '["portal", "education"]'),
('P1007', 'Finance Dashboard', 6, 3, 4, 'ACTIVE', '2025-09-15', NULL, 180000.00, '["finance", "dashboard"]'),
('P1008', 'People Analytics', 3, 2, 3, 'ACTIVE', '2025-10-01', NULL, 210000.00, '["hr", "analytics"]');

-- Employee/project assignments.
INSERT INTO employee_projects (employee_id, project_id, role_name, allocation_percent, assigned_on) VALUES
(5, 1, 'Project Manager', 35.00, '2025-01-15'),
(6, 1, 'Senior Engineer', 70.00, '2025-01-20'),
(7, 1, 'Data Lead', 60.00, '2025-01-15'),
(8, 1, 'Data Analyst', 80.00, '2025-02-01'),
(6, 2, 'Backend Lead', 50.00, '2025-03-01'),
(13, 2, 'Software Engineer', 90.00, '2025-03-05'),
(5, 2, 'Project Manager', 30.00, '2025-03-01'),
(6, 3, 'Engineer', 60.00, '2024-02-01'),
(7, 4, 'Data Lead', 55.00, '2025-06-15'),
(8, 4, 'Analyst', 75.00, '2025-06-20'),
(13, 4, 'Engineer', 45.00, '2025-07-01'),
(5, 5, 'Project Manager', 25.00, '2025-08-01'),
(6, 5, 'Engineer', 30.00, '2025-08-01'),
(15, 7, 'Finance Lead', 80.00, '2025-09-15'),
(4, 7, 'Executive Sponsor', 10.00, '2025-09-15'),
(3, 8, 'Executive Sponsor', 15.00, '2025-10-01'),
(7, 8, 'Data Lead', 40.00, '2025-10-01'),
(8, 8, 'Analyst', 85.00, '2025-10-02');

-- Products.
INSERT INTO products (sku, product_name, category, unit_price, cost_price, stock_reorder_level, attributes) VALUES
('LAP-001', 'Business Laptop 14', 'Laptops', 95000.00, 72000.00, 15, '{"ram_gb": 16, "storage_gb": 512, "color": "silver"}'),
('LAP-002', 'Developer Laptop 16', 'Laptops', 135000.00, 100000.00, 10, '{"ram_gb": 32, "storage_gb": 1000, "color": "black"}'),
('MON-001', '27 Inch Monitor', 'Monitors', 32000.00, 22000.00, 20, '{"size_in": 27, "resolution": "4K"}'),
('KEY-001', 'Mechanical Keyboard', 'Accessories', 8500.00, 5000.00, 30, '{"switch": "tactile", "layout": "ANSI"}'),
('MOU-001', 'Wireless Mouse', 'Accessories', 3200.00, 1800.00, 40, '{"dpi": 26000, "wireless": true}'),
('PHN-001', 'Business Phone', 'Phones', 72000.00, 50000.00, 15, '{"storage_gb": 256, "5g": true}'),
('TAB-001', 'Professional Tablet', 'Tablets', 58000.00, 42000.00, 12, '{"storage_gb": 256, "pen": true}'),
('WEB-001', '4K Webcam', 'Accessories', 12500.00, 7500.00, 25, '{"resolution": "4K", "microphone": true}'),
('DOC-001', 'USB-C Dock', 'Accessories', 14500.00, 8500.00, 20, '{"ports": 11, "display_support": 2}'),
('CHR-001', 'Ergonomic Chair', 'Furniture', 42000.00, 28000.00, 10, '{"material": "mesh", "adjustable": true}');

-- Suppliers.
INSERT INTO suppliers (supplier_name, contact_email, country_code, rating, metadata) VALUES
('Northwind Components', 'sales@northwind.example', 'IN', 4.60, '{"preferred": true, "payment_terms": 30}'),
('Global Tech Source', 'sales@globaltech.example', 'SG', 4.20, '{"preferred": false, "payment_terms": 45}'),
('Metro Office Supply', 'sales@metrooffice.example', 'US', 4.00, '{"preferred": false, "payment_terms": 30}'),
('Alpine Devices', 'sales@alpinedevices.example', 'GB', 4.80, '{"preferred": true, "payment_terms": 60}');

INSERT INTO product_suppliers (product_id, supplier_id, supplier_sku, lead_time_days, last_cost) VALUES
(1, 1, 'NW-LAP14', 12, 72000.00), (1, 2, 'GTS-L14', 18, 73000.00),
(2, 1, 'NW-LAP16', 14, 100000.00), (2, 4, 'ALP-L16', 10, 99000.00),
(3, 2, 'GTS-M27', 20, 22000.00), (3, 3, 'MOS-M27', 15, 22500.00),
(4, 3, 'MOS-KEY', 10, 5000.00),
(5, 3, 'MOS-MOU', 8, 1800.00),
(6, 4, 'ALP-PHN', 21, 50000.00),
(7, 4, 'ALP-TAB', 21, 42000.00),
(8, 2, 'GTS-WEB', 12, 7500.00),
(9, 1, 'NW-DOCK', 10, 8500.00),
(10, 3, 'MOS-CHR', 14, 28000.00);

-- Warehouses and inventory.
INSERT INTO warehouses (warehouse_code, warehouse_name, city, country_code) VALUES
('WH-MUM', 'Mumbai Central Warehouse', 'Mumbai', 'IN'),
('WH-BLR', 'Bengaluru Warehouse', 'Bengaluru', 'IN'),
('WH-SIN', 'Singapore Warehouse', 'Singapore', 'SG');

INSERT INTO inventory (warehouse_id, product_id, quantity, reserved_quantity, last_counted_at) VALUES
(1, 1, 48, 6, '2026-09-28 10:00:00'),
(1, 2, 14, 2, '2026-09-28 10:10:00'),
(1, 3, 36, 4, '2026-09-28 10:20:00'),
(1, 4, 80, 10, '2026-09-28 10:30:00'),
(1, 5, 120, 12, '2026-09-28 10:40:00'),
(1, 6, 25, 3, '2026-09-28 10:50:00'),
(2, 1, 22, 3, '2026-09-29 09:00:00'),
(2, 3, 18, 2, '2026-09-29 09:15:00'),
(2, 7, 16, 1, '2026-09-29 09:30:00'),
(2, 8, 8, 1, '2026-09-29 09:45:00'),
(3, 2, 9, 2, '2026-09-29 14:00:00'),
(3, 6, 18, 1, '2026-09-29 14:15:00'),
(3, 9, 25, 4, '2026-09-29 14:30:00'),
(3, 10, 7, 1, '2026-09-29 14:45:00');

-- Customers.
INSERT INTO customers
(customer_code, first_name, last_name, email, phone, city, country_code, loyalty_tier, preferences)
VALUES
('C001', 'Ananya', 'Iyer', 'ananya.iyer@example.com', '+91-9880000001', 'Mumbai', 'IN', 'GOLD',
 '{"newsletter": true, "favorite_categories": ["Laptops", "Accessories"]}'),
('C002', 'Rahul', 'Verma', 'rahul.verma@example.com', '+91-9880000002', 'Delhi', 'IN', 'SILVER',
 '{"newsletter": false, "favorite_categories": ["Phones"]}'),
('C003', 'Sarah', 'Wilson', 'sarah.wilson@example.com', '+44-7880000003', 'London', 'GB', 'PLATINUM',
 '{"newsletter": true, "favorite_categories": ["Monitors", "Furniture"]}'),
('C004', 'Michael', 'Chen', 'michael.chen@example.com', '+65-8880000004', 'Singapore', 'SG', 'GOLD',
 '{"newsletter": true, "favorite_categories": ["Tablets"]}'),
('C005', 'John', 'Miller', 'john.miller@example.com', '+1-8880000005', 'New York', 'US', 'STANDARD',
 '{"newsletter": false, "favorite_categories": ["Accessories"]}'),
('C006', 'Fatima', 'Khan', 'fatima.khan@example.com', '+91-9880000006', 'Pune', 'IN', 'SILVER',
 '{"newsletter": true, "favorite_categories": ["Laptops"]}'),
('C007', 'Diego', 'Garcia', 'diego.garcia@example.com', '+1-8880000007', 'Austin', 'US', 'GOLD',
 '{"newsletter": true, "favorite_categories": ["Phones", "Monitors"]}'),
('C008', 'Mei', 'Lim', 'mei.lim@example.com', '+65-8880000008', 'Singapore', 'SG', 'PLATINUM',
 '{"newsletter": true, "favorite_categories": ["Laptops", "Tablets"]}');

-- Orders. Order totals will be populated using a later query; this demonstrates
-- aggregate-driven DML and later a trigger that keeps them in sync.
INSERT INTO orders
(order_number, customer_id, sales_employee_id, order_date, status, shipping_city, shipping_country_code, notes)
VALUES
('ORD-10001', 1, 9, '2026-01-05 10:30:00', 'COMPLETED', 'Mumbai', 'IN', 'Priority enterprise delivery'),
('ORD-10002', 2, 9, '2026-01-18 15:15:00', 'PAID', 'Delhi', 'IN', 'Leave at reception'),
('ORD-10003', 3, 10, '2026-02-02 09:45:00', 'COMPLETED', 'London', 'GB', NULL),
('ORD-10004', 4, 10, '2026-02-19 12:05:00', 'SHIPPED', 'Singapore', 'SG', 'International shipping'),
('ORD-10005', 5, 10, '2026-03-04 18:20:00', 'CANCELLED', 'New York', 'US', 'Customer cancelled'),
('ORD-10006', 6, 9, '2026-03-17 11:25:00', 'COMPLETED', 'Pune', 'IN', NULL),
('ORD-10007', 7, 10, '2026-04-01 16:40:00', 'PAID', 'Austin', 'US', 'Corporate buyer'),
('ORD-10008', 8, 10, '2026-04-18 14:10:00', 'COMPLETED', 'Singapore', 'SG', NULL),
('ORD-10009', 1, 9, '2026-05-12 13:50:00', 'SHIPPED', 'Mumbai', 'IN', NULL),
('ORD-10010', 3, 10, '2026-06-20 10:05:00', 'COMPLETED', 'London', 'GB', 'Use existing billing profile');

INSERT INTO order_items (order_id, product_id, quantity, unit_price, discount_percent) VALUES
(1, 1, 2, 95000.00, 5.00),
(1, 4, 2, 8500.00, 0.00),
(2, 6, 1, 72000.00, 3.00),
(2, 5, 2, 3200.00, 0.00),
(3, 3, 3, 32000.00, 8.00),
(3, 10, 2, 42000.00, 5.00),
(4, 7, 2, 58000.00, 2.50),
(4, 9, 1, 14500.00, 0.00),
(5, 2, 1, 135000.00, 0.00),
(6, 1, 1, 95000.00, 7.50),
(6, 8, 2, 12500.00, 0.00),
(7, 2, 2, 135000.00, 10.00),
(7, 3, 2, 32000.00, 5.00),
(8, 6, 1, 72000.00, 0.00),
(8, 7, 1, 58000.00, 0.00),
(8, 10, 1, 42000.00, 12.00),
(9, 4, 4, 8500.00, 0.00),
(9, 9, 2, 14500.00, 5.00),
(10, 3, 1, 32000.00, 0.00),
(10, 10, 1, 42000.00, 0.00);

-- Calculate order subtotal, tax, discount, and total from line items.
-- UPDATE + JOIN is a key MySQL DML pattern.
UPDATE orders o
JOIN (
    SELECT order_id,
           SUM(quantity * unit_price) AS gross_subtotal,
           SUM(line_total) AS net_subtotal
    FROM order_items
    GROUP BY order_id
) x ON x.order_id = o.order_id
SET o.subtotal = x.gross_subtotal,
    o.discount_amount = x.gross_subtotal - x.net_subtotal,
    o.tax_amount = ROUND(x.net_subtotal * 0.18, 2),
    o.total_amount = ROUND(x.net_subtotal * 1.18, 2);

-- Payments.
INSERT INTO payments
(order_id, payment_date, amount, payment_method, payment_status, transaction_reference)
SELECT order_id, order_date, total_amount,
       CASE MOD(order_id, 4)
           WHEN 0 THEN 'CARD'
           WHEN 1 THEN 'UPI'
           WHEN 2 THEN 'BANK_TRANSFER'
           ELSE 'WALLET'
       END,
       CASE status
           WHEN 'CANCELLED' THEN 'REFUNDED'
           ELSE 'SUCCESS'
       END,
       CONCAT('TXN-', order_number)
FROM orders;

-- Timesheet data.
INSERT INTO timesheets (employee_id, project_id, work_date, hours, billable, description) VALUES
(6, 1, '2026-01-05', 7.50, TRUE, 'Pipeline development'),
(7, 1, '2026-01-05', 6.00, TRUE, 'Data model work'),
(8, 1, '2026-01-05', 7.00, TRUE, 'Dashboard validation'),
(6, 2, '2026-01-06', 6.50, TRUE, 'API development'),
(13, 2, '2026-01-06', 8.00, TRUE, 'Application development'),
(7, 4, '2026-01-07', 5.50, TRUE, 'Data quality rules'),
(8, 4, '2026-01-07', 7.50, TRUE, 'Report development'),
(15, 7, '2026-01-08', 6.00, TRUE, 'Financial model'),
(4, 7, '2026-01-08', 2.00, FALSE, 'Executive review'),
(3, 8, '2026-01-08', 2.50, FALSE, 'Stakeholder meeting'),
(7, 8, '2026-01-08', 4.00, TRUE, 'People metrics'),
(8, 8, '2026-01-08', 7.00, TRUE, 'Analytics');

-- Expenses.
INSERT INTO expenses (employee_id, project_id, expense_date, category, amount, description, status, metadata) VALUES
(6, 1, '2026-01-06', 'Travel', 8400.00, 'Client workshop travel', 'APPROVED', '{"currency": "INR", "reimbursable": true}'),
(7, 4, '2026-01-10', 'Conference', 12500.00, 'Data conference registration', 'APPROVED', '{"currency": "INR", "reimbursable": true}'),
(8, 8, '2026-01-12', 'Software', 3200.00, 'Analytics tool subscription', 'SUBMITTED', '{"currency": "INR", "reimbursable": true}'),
(9, NULL, '2026-01-14', 'Travel', 15600.00, 'Client visit', 'PAID', '{"currency": "INR", "reimbursable": true}'),
(10, 2, '2026-01-15', 'Travel', 9200.00, 'Customer meeting', 'APPROVED', '{"currency": "INR", "reimbursable": true}'),
(15, 7, '2026-01-20', 'Software', 4500.00, 'Financial analysis package', 'REJECTED', '{"currency": "INR", "reimbursable": false}');

-- Payroll sample data. One row per employee for two payroll months.
INSERT INTO payroll_records (employee_id, payroll_month, gross_salary, tax_amount, net_salary)
SELECT employee_id, '2026-08-01', current_salary / 12, ROUND(current_salary / 12 * 0.20, 2),
       ROUND(current_salary / 12 * 0.80, 2)
FROM employees
WHERE is_active = TRUE;

INSERT INTO payroll_records (employee_id, payroll_month, gross_salary, tax_amount, net_salary)
SELECT employee_id, '2026-09-01', current_salary / 12, ROUND(current_salary / 12 * 0.20, 2),
       ROUND(current_salary / 12 * 0.80, 2)
FROM employees
WHERE is_active = TRUE;

-- ============================================================================
-- 03. METADATA / INSPECTION COMMANDS
-- ============================================================================

-- List databases visible to the current account.
SHOW DATABASES;

-- List tables in the current database.
SHOW TABLES;

-- Inspect column definitions.
DESCRIBE employees;
DESC orders;

-- Show the exact CREATE TABLE definition generated by MySQL.
SHOW CREATE TABLE employees;

-- Show indexes defined on a table.
SHOW INDEX FROM employees;

-- Query information_schema for column metadata.
SELECT table_name, column_name, data_type, is_nullable, column_key
FROM information_schema.columns
WHERE table_schema = DATABASE()
ORDER BY table_name, ordinal_position;

-- Query information_schema for foreign-key relationships.
SELECT table_name, constraint_name, column_name, referenced_table_name, referenced_column_name
FROM information_schema.key_column_usage
WHERE table_schema = DATABASE()
  AND referenced_table_name IS NOT NULL
ORDER BY table_name, constraint_name;

-- ============================================================================
-- 04. INSERT / UPDATE / DELETE / REPLACE / DML PATTERNS
-- ============================================================================

-- 4.1 Insert one row.
INSERT INTO skills (skill_name, skill_category)
VALUES ('Public Speaking', 'Communication');

-- Capture the generated id for the row just inserted.
SELECT LAST_INSERT_ID() AS new_skill_id;

-- 4.2 Insert multiple rows in one statement.
INSERT INTO skills (skill_name, skill_category) VALUES
('Negotiation', 'Communication'),
('Testing', 'Engineering'),
('Kubernetes', 'DevOps');

-- 4.3 Insert selected columns and rely on defaults for other columns.
INSERT INTO suppliers (supplier_name, country_code)
VALUES ('Training Supplier', 'IN');

-- 4.4 INSERT ... SELECT: copy data into a reporting-style table.
CREATE TABLE IF NOT EXISTS project_budget_snapshot (
    project_id INT UNSIGNED PRIMARY KEY,
    project_name VARCHAR(150) NOT NULL,
    budget DECIMAL(14,2) NOT NULL,
    captured_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

TRUNCATE TABLE project_budget_snapshot;

INSERT INTO project_budget_snapshot (project_id, project_name, budget)
SELECT project_id, project_name, budget
FROM projects
WHERE status IN ('ACTIVE', 'PLANNED');

SELECT * FROM project_budget_snapshot ORDER BY budget DESC;

-- 4.5 UPDATE one row using a primary key.
UPDATE customers
SET loyalty_tier = 'GOLD'
WHERE customer_id = 6;

-- 4.6 UPDATE multiple rows using a predicate.
UPDATE products
SET is_active = TRUE
WHERE category = 'Accessories';

-- 4.7 UPDATE using CASE for conditional logic.
UPDATE employees
SET current_salary = current_salary * CASE
    WHEN department_id = 1 THEN 1.02
    WHEN department_id = 6 THEN 1.03
    ELSE 1.01
END
WHERE employee_id IN (6, 7, 8, 13);

-- Keep salary_history consistent with the training update.
INSERT INTO salary_history (employee_id, effective_from, effective_to, salary, change_reason)
SELECT employee_id, '2026-10-01', NULL, current_salary,
       'Training lab adjustment'
FROM employees
WHERE employee_id IN (6, 7, 8, 13);

-- 4.8 UPDATE using a JOIN.
UPDATE products p
JOIN (
    SELECT product_id, MAX(last_cost) AS latest_cost
    FROM product_suppliers
    GROUP BY product_id
) s ON s.product_id = p.product_id
SET p.cost_price = LEAST(p.cost_price, s.latest_cost)
WHERE s.latest_cost IS NOT NULL;

-- 4.9 DELETE safely inside a transaction and roll it back so later sections keep their data.
START TRANSACTION;
DELETE FROM skills WHERE skill_name IN ('Public Speaking', 'Negotiation', 'Testing', 'Kubernetes');
SELECT ROW_COUNT() AS deleted_skill_rows;
ROLLBACK;

-- 4.10 DELETE with JOIN, again rolled back as a lab demonstration.
START TRANSACTION;
DELETE e
FROM employee_skills es
JOIN employees e ON e.employee_id = es.employee_id
WHERE e.employee_id = 15 AND es.skill_id = 9;
SELECT ROW_COUNT() AS deleted_rows_from_join_delete;
ROLLBACK;

-- 4.11 REPLACE: MySQL-specific operation. Demonstrated on a throwaway table.
CREATE TABLE replace_demo (
    id INT PRIMARY KEY,
    value_text VARCHAR(100) NOT NULL
);
INSERT INTO replace_demo VALUES (1, 'first value');
REPLACE INTO replace_demo VALUES (1, 'replacement value');
SELECT * FROM replace_demo;
DROP TABLE replace_demo;

-- 4.12 INSERT ... ON DUPLICATE KEY UPDATE (upsert pattern).
INSERT INTO suppliers (supplier_name, contact_email, country_code, rating)
VALUES ('Northwind Components', 'updated@northwind.example', 'IN', 4.70)
ON DUPLICATE KEY UPDATE
    contact_email = VALUES(contact_email),
    rating = VALUES(rating);

-- ============================================================================
-- 05. SELECT FUNDAMENTALS
-- ============================================================================

-- Select all columns. Useful while exploring; prefer explicit columns in production.
SELECT * FROM employees;

-- Select only required columns.
SELECT employee_id, first_name, last_name, job_title
FROM employees;

-- Column aliases make result sets easier to read.
SELECT employee_id AS id,
       CONCAT(first_name, ' ', last_name) AS full_name,
       current_salary AS annual_salary
FROM employees;

-- DISTINCT removes duplicate result values.
SELECT DISTINCT country_code
FROM customers
ORDER BY country_code;

-- WHERE filters rows before grouping.
SELECT employee_id, first_name, last_name, current_salary
FROM employees
WHERE current_salary > 100000;

-- Comparison operators: =, !=, <>, >, >=, <, <=.
SELECT *
FROM employees
WHERE department_id = 1
  AND current_salary >= 90000;

-- OR + parentheses control boolean precedence.
SELECT *
FROM employees
WHERE department_id = 1
  AND (current_salary >= 100000 OR job_title LIKE '%Manager%');

-- BETWEEN is inclusive at both ends.
SELECT employee_id, first_name, current_salary
FROM employees
WHERE current_salary BETWEEN 70000 AND 100000
ORDER BY current_salary;

-- IN is concise for membership checks.
SELECT *
FROM employees
WHERE department_id IN (1, 6);

-- NOT IN excludes a set. Be aware that NULL semantics can affect NOT IN.
SELECT *
FROM employees
WHERE employee_id NOT IN (1, 2, 3);

-- LIKE wildcard: % = any number of characters, _ = exactly one character.
SELECT *
FROM customers
WHERE last_name LIKE 'M%';

SELECT *
FROM employees
WHERE first_name LIKE '_a%';

-- REGEXP / REGEXP_LIKE performs regular-expression matching.
SELECT email
FROM employees
WHERE REGEXP_LIKE(email, '^[a-z]+\\.[a-z]+@example\\.com$');

-- ORDER BY supports multiple keys and ASC/DESC.
SELECT employee_id, first_name, last_name, current_salary
FROM employees
ORDER BY current_salary DESC, last_name ASC;

-- LIMIT returns only a slice of the result set.
SELECT employee_id, first_name, last_name, current_salary
FROM employees
ORDER BY current_salary DESC
LIMIT 5;

-- LIMIT with OFFSET supports pagination.
SELECT employee_id, first_name, last_name
FROM employees
ORDER BY employee_id
LIMIT 5 OFFSET 5;

-- SQL three-valued logic: manager_id IS NULL finds top-level employees.
SELECT employee_id, first_name, last_name
FROM employees
WHERE manager_id IS NULL;

-- IS NOT NULL finds rows with a value.
SELECT employee_id, first_name, manager_id
FROM employees
WHERE manager_id IS NOT NULL;

-- NULL-safe equality operator <=> is a MySQL-specific tool.
SELECT 1 <=> NULL AS one_equals_null,
       NULL <=> NULL AS null_equals_null;

-- Use explicit boolean predicates.
SELECT employee_id, first_name, is_active
FROM employees
WHERE is_active = TRUE;

-- Aliases can also be used in ORDER BY.
SELECT CONCAT(first_name, ' ', last_name) AS full_name,
       current_salary * 1.10 AS projected_salary
FROM employees
ORDER BY projected_salary DESC;

-- ============================================================================
-- 06. FUNCTIONS: STRING / NUMERIC / DATE-TIME / CONDITIONAL / JSON
-- ============================================================================

-- String functions: CONCAT, UPPER, LOWER, CHAR_LENGTH, TRIM, SUBSTRING.
SELECT employee_id,
       CONCAT(first_name, ' ', last_name) AS full_name,
       UPPER(last_name) AS surname_upper,
       CHAR_LENGTH(email) AS email_length,
       LEFT(email, 5) AS email_prefix,
       SUBSTRING(email, 1, 5) AS email_substring
FROM employees;

-- REPLACE and TRIM are useful for data cleansing.
SELECT REPLACE(TRIM('  SQL Mastery  '), 'Mastery', 'Practice') AS cleaned_text;

-- String aggregation: GROUP_CONCAT.
SELECT d.department_name,
       GROUP_CONCAT(CONCAT(e.first_name, ' ', e.last_name)
                    ORDER BY e.last_name SEPARATOR ', ') AS employees
FROM departments d
LEFT JOIN employees e ON e.department_id = d.department_id
GROUP BY d.department_id, d.department_name
ORDER BY d.department_id;

-- Numeric functions: ROUND, CEIL, FLOOR, ABS, MOD, POWER, SQRT.
SELECT ROUND(1234.5678, 2) AS rounded_value,
       CEIL(12.1) AS ceiling_value,
       FLOOR(12.9) AS floor_value,
       ABS(-42) AS absolute_value,
       MOD(17, 5) AS remainder,
       POWER(2, 10) AS power_value,
       SQRT(81) AS square_root;

-- RAND generates pseudorandom values; avoid it for deterministic ordering.
SELECT employee_id, first_name, RAND() AS random_value
FROM employees
LIMIT 5;

-- Current date/time functions.
SELECT CURRENT_DATE() AS today,
       CURRENT_TIME() AS now_time,
       CURRENT_TIMESTAMP AS now_timestamp,
       UTC_TIMESTAMP() AS utc_timestamp;

-- Date arithmetic.
SELECT employee_id,
       hire_date,
       DATE_ADD(hire_date, INTERVAL 90 DAY) AS probation_end,
       TIMESTAMPDIFF(YEAR, hire_date, CURRENT_DATE()) AS years_with_company
FROM employees;

-- Date extraction.
SELECT order_id,
       order_date,
       YEAR(order_date) AS order_year,
       MONTH(order_date) AS order_month,
       QUARTER(order_date) AS order_quarter,
       DAYOFWEEK(order_date) AS day_of_week
FROM orders
ORDER BY order_date;

-- Formatting dates for presentation.
SELECT order_number,
       DATE_FORMAT(order_date, '%d-%b-%Y %H:%i') AS formatted_order_time
FROM orders;

-- String-to-date conversion.
SELECT STR_TO_DATE('06/10/2026', '%d/%m/%Y') AS parsed_date;

-- CASE expression for business rules.
SELECT employee_id,
       first_name,
       current_salary,
       CASE
           WHEN current_salary >= 150000 THEN 'Executive'
           WHEN current_salary >= 100000 THEN 'Senior'
           WHEN current_salary >= 70000 THEN 'Mid-level'
           ELSE 'Entry-level'
       END AS salary_band
FROM employees
ORDER BY current_salary DESC;

-- CASE can be used for conditional aggregates.
SELECT
    SUM(CASE WHEN status = 'COMPLETED' THEN 1 ELSE 0 END) AS completed_orders,
    SUM(CASE WHEN status = 'CANCELLED' THEN 1 ELSE 0 END) AS cancelled_orders,
    SUM(CASE WHEN status = 'PAID' THEN 1 ELSE 0 END) AS paid_orders
FROM orders;

-- COALESCE returns the first non-NULL value.
SELECT employee_id,
       first_name,
       COALESCE(phone, 'No phone available') AS phone_display
FROM employees;

-- NULLIF can intentionally turn a value into NULL, useful for avoiding divide-by-zero.
SELECT 100 / NULLIF(0, 0) AS safe_division;

-- IF and IFNULL are MySQL-specific convenience functions.
SELECT employee_id,
       first_name,
       IF(is_active, 'Active', 'Inactive') AS status_label
FROM employees;

SELECT employee_id, IFNULL(phone, 'N/A') AS phone
FROM employees;

-- JSON_EXTRACT / -> operators read JSON values.
SELECT employee_id,
       JSON_EXTRACT(profile, '$.remote') AS remote_flag,
       profile->'$.remote' AS remote_json
FROM employees
WHERE profile IS NOT NULL;

-- ->> returns an unquoted scalar from JSON.
SELECT employee_id,
       profile->>'$.region' AS region
FROM employees
WHERE profile->>'$.region' IS NOT NULL;

-- JSON_CONTAINS searches JSON arrays/objects.
SELECT employee_id, first_name, profile
FROM employees
WHERE JSON_CONTAINS(profile->'$.languages', JSON_QUOTE('English'));

-- JSON_SET modifies a JSON document in a query result.
SELECT employee_id,
       JSON_SET(profile, '$.training_status', 'required') AS updated_profile
FROM employees
LIMIT 5;

-- JSON_TABLE turns JSON arrays into relational rows.
SELECT e.employee_id, e.first_name, j.language
FROM employees e
CROSS JOIN JSON_TABLE(
    e.profile,
    '$.languages[*]' COLUMNS (
        language VARCHAR(50) PATH '$'
    )
) AS j
WHERE e.profile->'$.languages' IS NOT NULL
ORDER BY e.employee_id;

-- ============================================================================
-- 07. AGGREGATION / GROUP BY / HAVING / ROLLUP
-- ============================================================================

-- COUNT(*) counts rows; COUNT(column) ignores NULL values.
SELECT COUNT(*) AS employee_count,
       COUNT(manager_id) AS employees_with_manager
FROM employees;

-- Aggregate salary statistics.
SELECT COUNT(*) AS employees,
       MIN(current_salary) AS min_salary,
       MAX(current_salary) AS max_salary,
       AVG(current_salary) AS avg_salary,
       SUM(current_salary) AS total_salary
FROM employees;

-- GROUP BY department.
SELECT d.department_name,
       COUNT(e.employee_id) AS employee_count,
       ROUND(AVG(e.current_salary), 2) AS avg_salary,
       SUM(e.current_salary) AS payroll
FROM departments d
LEFT JOIN employees e ON e.department_id = d.department_id
GROUP BY d.department_id, d.department_name
ORDER BY payroll DESC;

-- HAVING filters groups after aggregation.
SELECT department_id,
       COUNT(*) AS employee_count,
       ROUND(AVG(current_salary), 2) AS avg_salary
FROM employees
GROUP BY department_id
HAVING AVG(current_salary) > 90000;

-- GROUP BY multiple columns.
SELECT country_code, loyalty_tier, COUNT(*) AS customers
FROM customers
GROUP BY country_code, loyalty_tier
ORDER BY country_code, loyalty_tier;

-- ROLLUP adds subtotal/total rows for hierarchical grouping.
SELECT country_code,
       loyalty_tier,
       COUNT(*) AS customer_count
FROM customers
GROUP BY country_code, loyalty_tier WITH ROLLUP;

-- GROUPING() identifies a NULL created by ROLLUP rather than a stored NULL.
SELECT country_code,
       loyalty_tier,
       GROUPING(country_code) AS country_is_total,
       GROUPING(loyalty_tier) AS tier_is_total,
       COUNT(*) AS customer_count
FROM customers
GROUP BY country_code, loyalty_tier WITH ROLLUP;

-- Aggregate with conditional logic.
SELECT c.customer_id,
       CONCAT(c.first_name, ' ', c.last_name) AS customer_name,
       SUM(CASE WHEN o.status <> 'CANCELLED' THEN o.total_amount ELSE 0 END) AS valid_order_value,
       COUNT(CASE WHEN o.status = 'COMPLETED' THEN 1 END) AS completed_order_count
FROM customers c
LEFT JOIN orders o ON o.customer_id = c.customer_id
GROUP BY c.customer_id, customer_name
ORDER BY valid_order_value DESC;

-- ============================================================================
-- 08. JOINS
-- ============================================================================

-- INNER JOIN returns matching rows on both sides.
SELECT e.employee_id,
       CONCAT(e.first_name, ' ', e.last_name) AS employee_name,
       d.department_name
FROM employees e
INNER JOIN departments d ON d.department_id = e.department_id
ORDER BY e.employee_id;

-- LEFT JOIN keeps every row from the left table even if there is no match.
SELECT d.department_name,
       e.employee_id,
       CONCAT(e.first_name, ' ', e.last_name) AS employee_name
FROM departments d
LEFT JOIN employees e ON e.department_id = d.department_id
ORDER BY d.department_id, e.employee_id;

-- RIGHT JOIN is supported, though many teams prefer rewriting it as LEFT JOIN.
SELECT d.department_name,
       e.employee_id,
       CONCAT(e.first_name, ' ', e.last_name) AS employee_name
FROM employees e
RIGHT JOIN departments d ON d.department_id = e.department_id
ORDER BY d.department_id, e.employee_id;

-- SELF JOIN: employee -> manager.
SELECT e.employee_id,
       CONCAT(e.first_name, ' ', e.last_name) AS employee_name,
       CONCAT(m.first_name, ' ', m.last_name) AS manager_name
FROM employees e
LEFT JOIN employees m ON m.employee_id = e.manager_id
ORDER BY e.employee_id;

-- SELF JOIN + inequality: find pairs of employees in the same department.
SELECT e1.first_name AS employee_a,
       e2.first_name AS employee_b,
       e1.department_id
FROM employees e1
JOIN employees e2
  ON e1.department_id = e2.department_id
 AND e1.employee_id < e2.employee_id
ORDER BY e1.department_id, employee_a, employee_b;

-- CROSS JOIN produces a Cartesian product; useful when every combination is intended.
SELECT w.warehouse_name, p.product_name
FROM warehouses w
CROSS JOIN products p
WHERE p.category = 'Accessories'
ORDER BY w.warehouse_id, p.product_id;

-- Many-to-many join: employees -> employee_projects -> projects.
SELECT e.employee_id,
       CONCAT(e.first_name, ' ', e.last_name) AS employee_name,
       p.project_name,
       ep.role_name,
       ep.allocation_percent
FROM employees e
JOIN employee_projects ep ON ep.employee_id = e.employee_id
JOIN projects p ON p.project_id = ep.project_id
ORDER BY e.employee_id, p.project_id;

-- Multi-table order report.
SELECT o.order_number,
       CONCAT(c.first_name, ' ', c.last_name) AS customer_name,
       CONCAT(e.first_name, ' ', e.last_name) AS salesperson,
       o.status,
       o.total_amount
FROM orders o
JOIN customers c ON c.customer_id = o.customer_id
LEFT JOIN employees e ON e.employee_id = o.sales_employee_id
ORDER BY o.order_date;

-- Anti-join: find employees with no assigned projects.
SELECT e.employee_id, e.first_name, e.last_name
FROM employees e
LEFT JOIN employee_projects ep ON ep.employee_id = e.employee_id
WHERE ep.employee_id IS NULL;

-- Another anti-join: products with no inventory.
SELECT p.product_id, p.product_name
FROM products p
LEFT JOIN inventory i ON i.product_id = p.product_id
WHERE i.product_id IS NULL;

-- Semi-join style: DISTINCT employees who have worked on an active project.
SELECT DISTINCT e.employee_id, e.first_name, e.last_name
FROM employees e
JOIN employee_projects ep ON ep.employee_id = e.employee_id
JOIN projects p ON p.project_id = ep.project_id
WHERE p.status = 'ACTIVE';

-- Simulate FULL OUTER JOIN in MySQL using LEFT JOIN + UNION ALL + anti-join.
-- The second branch returns rows found only on the right side.
SELECT d.department_id, d.department_name, e.employee_id
FROM departments d
LEFT JOIN employees e ON e.department_id = d.department_id
UNION ALL
SELECT d.department_id, d.department_name, e.employee_id
FROM employees e
LEFT JOIN departments d ON d.department_id = e.department_id
WHERE d.department_id IS NULL;

-- ============================================================================
-- 09. SET OPERATIONS
-- ============================================================================

-- UNION removes duplicate rows between result sets.
SELECT city FROM customers
UNION
SELECT city FROM clients;

-- UNION ALL retains duplicates and is usually cheaper when deduplication is unnecessary.
SELECT country_code FROM customers
UNION ALL
SELECT country_code FROM clients;

-- INTERSECT returns rows common to both result sets (MySQL 8.0.31+).
SELECT city FROM customers
INTERSECT
SELECT city FROM clients;

-- EXCEPT returns rows from the first set that are absent from the second (MySQL 8.0.31+).
SELECT city FROM clients
EXCEPT
SELECT city FROM customers;

-- Parenthesized query expressions make precedence explicit when combining set operators.
(SELECT city FROM customers WHERE country_code = 'IN')
UNION
(SELECT city FROM clients WHERE country_code = 'IN');

-- ============================================================================
-- 10. SUBQUERIES
-- ============================================================================

-- Scalar subquery: compare every employee to the company-wide average.
SELECT employee_id,
       first_name,
       current_salary
FROM employees
WHERE current_salary > (SELECT AVG(current_salary) FROM employees)
ORDER BY current_salary DESC;

-- IN subquery: employees whose department is located in India.
SELECT e.employee_id, e.first_name, e.last_name
FROM employees e
WHERE e.location_id IN (
    SELECT location_id
    FROM locations
    WHERE country_code = 'IN'
);

-- EXISTS: customers with at least one completed order.
SELECT c.customer_id, c.first_name, c.last_name
FROM customers c
WHERE EXISTS (
    SELECT 1
    FROM orders o
    WHERE o.customer_id = c.customer_id
      AND o.status = 'COMPLETED'
);

-- NOT EXISTS: customers with no cancelled orders.
SELECT c.customer_id, c.first_name, c.last_name
FROM customers c
WHERE NOT EXISTS (
    SELECT 1
    FROM orders o
    WHERE o.customer_id = c.customer_id
      AND o.status = 'CANCELLED'
);

-- Correlated subquery: each employee compared to their department average.
SELECT e.employee_id,
       e.first_name,
       e.current_salary,
       (
           SELECT AVG(e2.current_salary)
           FROM employees e2
           WHERE e2.department_id = e.department_id
       ) AS department_avg_salary
FROM employees e
ORDER BY e.department_id, e.current_salary DESC;

-- Find the highest-paid employee(s) in each department using a correlated subquery.
SELECT e.employee_id, e.first_name, e.last_name, e.department_id, e.current_salary
FROM employees e
WHERE e.current_salary = (
    SELECT MAX(e2.current_salary)
    FROM employees e2
    WHERE e2.department_id = e.department_id
);

-- Derived table: aggregate first, then filter/project outside.
SELECT x.department_id, x.avg_salary
FROM (
    SELECT department_id, AVG(current_salary) AS avg_salary
    FROM employees
    GROUP BY department_id
) AS x
WHERE x.avg_salary > 90000;

-- Nested subquery: top project budgets above the average budget.
SELECT project_id, project_name, budget
FROM projects
WHERE budget > (
    SELECT AVG(budget)
    FROM projects
);

-- Correlated EXISTS across three tables.
SELECT p.project_id, p.project_name
FROM projects p
WHERE EXISTS (
    SELECT 1
    FROM employee_projects ep
    JOIN employees e ON e.employee_id = ep.employee_id
    WHERE ep.project_id = p.project_id
      AND e.current_salary > 100000
);

-- ============================================================================
-- 11. CTEs + RECURSIVE CTEs
-- ============================================================================

-- Non-recursive CTE: make complex logic easier to read.
WITH department_stats AS (
    SELECT department_id,
           COUNT(*) AS employee_count,
           AVG(current_salary) AS avg_salary
    FROM employees
    GROUP BY department_id
)
SELECT d.department_name,
       ds.employee_count,
       ROUND(ds.avg_salary, 2) AS avg_salary
FROM departments d
JOIN department_stats ds ON ds.department_id = d.department_id
ORDER BY ds.avg_salary DESC;

-- Multiple CTEs can feed one another.
WITH customer_order_totals AS (
    SELECT customer_id,
           SUM(CASE WHEN status <> 'CANCELLED' THEN total_amount ELSE 0 END) AS total_spend
    FROM orders
    GROUP BY customer_id
), ranked_customers AS (
    SELECT customer_id,
           total_spend,
           DENSE_RANK() OVER (ORDER BY total_spend DESC) AS spend_rank
    FROM customer_order_totals
)
SELECT c.customer_id,
       CONCAT(c.first_name, ' ', c.last_name) AS customer_name,
       rc.total_spend,
       rc.spend_rank
FROM customers c
JOIN ranked_customers rc ON rc.customer_id = c.customer_id
ORDER BY rc.spend_rank, customer_name;

-- CTE directly before an UPDATE: update employees based on aggregate criteria.
WITH department_salary AS (
    SELECT department_id, AVG(current_salary) AS avg_salary
    FROM employees
    GROUP BY department_id
)
UPDATE employees e
JOIN department_salary ds ON ds.department_id = e.department_id
SET e.profile = JSON_SET(COALESCE(e.profile, JSON_OBJECT()), '$.above_department_average',
                         e.current_salary > ds.avg_salary);

-- Recursive CTE: traverse the employee management hierarchy.
WITH RECURSIVE employee_tree AS (
    -- Anchor rows: top-level managers.
    SELECT employee_id,
           manager_id,
           CONCAT(first_name, ' ', last_name) AS employee_name,
           0 AS depth,
           CAST(employee_id AS CHAR(200)) AS path
    FROM employees
    WHERE manager_id IS NULL

    UNION ALL

    -- Recursive member: add direct reports to the rows discovered so far.
    SELECT e.employee_id,
           e.manager_id,
           CONCAT(e.first_name, ' ', e.last_name),
           et.depth + 1,
           CONCAT(et.path, ' > ', e.employee_id)
    FROM employees e
    JOIN employee_tree et ON e.manager_id = et.employee_id
)
SELECT employee_id, manager_id, employee_name, depth, path
FROM employee_tree
ORDER BY path;

-- Recursive CTE for generating a number sequence.
WITH RECURSIVE numbers AS (
    SELECT 1 AS n
    UNION ALL
    SELECT n + 1
    FROM numbers
    WHERE n < 10
)
SELECT n FROM numbers;

-- Recursive CTE + date series: create month starts for a reporting window.
WITH RECURSIVE months AS (
    SELECT DATE('2026-01-01') AS month_start
    UNION ALL
    SELECT DATE_ADD(month_start, INTERVAL 1 MONTH)
    FROM months
    WHERE month_start < '2026-12-01'
)
SELECT month_start FROM months;

-- ============================================================================
-- 12. WINDOW FUNCTIONS / ANALYTICS
-- ============================================================================

-- ROW_NUMBER gives each row a unique sequence within each department.
SELECT employee_id,
       department_id,
       first_name,
       current_salary,
       ROW_NUMBER() OVER (
           PARTITION BY department_id
           ORDER BY current_salary DESC
       ) AS department_salary_position
FROM employees
ORDER BY department_id, department_salary_position;

-- RANK leaves gaps after ties; DENSE_RANK does not.
SELECT employee_id,
       current_salary,
       RANK() OVER (ORDER BY current_salary DESC) AS salary_rank,
       DENSE_RANK() OVER (ORDER BY current_salary DESC) AS dense_salary_rank
FROM employees
ORDER BY current_salary DESC;

-- NTILE divides employees into four salary buckets.
SELECT employee_id,
       current_salary,
       NTILE(4) OVER (ORDER BY current_salary DESC) AS salary_quartile
FROM employees
ORDER BY current_salary DESC;

-- LAG compares the current employee salary with the previous row.
SELECT employee_id,
       first_name,
       current_salary,
       LAG(current_salary) OVER (ORDER BY current_salary) AS previous_salary,
       current_salary - LAG(current_salary) OVER (ORDER BY current_salary) AS salary_delta
FROM employees
ORDER BY current_salary;

-- LEAD looks ahead to the next row.
SELECT employee_id,
       first_name,
       hire_date,
       LEAD(hire_date) OVER (ORDER BY hire_date) AS next_hire_date
FROM employees
ORDER BY hire_date;

-- Running total of order revenue.
SELECT order_number,
       order_date,
       total_amount,
       SUM(total_amount) OVER (
           ORDER BY order_date, order_id
           ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
       ) AS running_revenue
FROM orders
WHERE status <> 'CANCELLED'
ORDER BY order_date, order_id;

-- Average order value over a moving three-order window.
SELECT order_number,
       order_date,
       total_amount,
       ROUND(
           AVG(total_amount) OVER (
               ORDER BY order_date, order_id
               ROWS BETWEEN 2 PRECEDING AND CURRENT ROW
           ), 2
       ) AS moving_3_order_avg
FROM orders
WHERE status <> 'CANCELLED'
ORDER BY order_date, order_id;

-- PARTITION BY + aggregate window function: department payroll share.
SELECT e.employee_id,
       e.first_name,
       e.department_id,
       e.current_salary,
       ROUND(
           100 * e.current_salary /
           SUM(e.current_salary) OVER (PARTITION BY e.department_id),
           2
       ) AS pct_of_department_payroll
FROM employees e
ORDER BY e.department_id, e.current_salary DESC;

-- Window function over grouped monthly revenue.
WITH monthly_revenue AS (
    SELECT DATE_FORMAT(order_date, '%Y-%m-01') AS month_start,
           SUM(total_amount) AS revenue
    FROM orders
    WHERE status <> 'CANCELLED'
    GROUP BY DATE_FORMAT(order_date, '%Y-%m-01')
)
SELECT month_start,
       revenue,
       LAG(revenue) OVER (ORDER BY month_start) AS previous_month_revenue,
       revenue - LAG(revenue) OVER (ORDER BY month_start) AS revenue_change
FROM monthly_revenue
ORDER BY month_start;

-- Named window specification avoids repeating PARTITION/ORDER clauses.
SELECT employee_id,
       department_id,
       current_salary,
       ROW_NUMBER() OVER w AS row_num,
       RANK() OVER w AS rank_num
FROM employees
WINDOW w AS (
    PARTITION BY department_id
    ORDER BY current_salary DESC
)
ORDER BY department_id, row_num;

-- Top 2 earners per department: window function + outer filter.
WITH ranked AS (
    SELECT e.*,
           ROW_NUMBER() OVER (
               PARTITION BY department_id
               ORDER BY current_salary DESC
           ) AS rn
    FROM employees e
)
SELECT *
FROM ranked
WHERE rn <= 2
ORDER BY department_id, rn;

-- ============================================================================
-- 13. VIEWS
-- ============================================================================

-- Basic reporting view.
CREATE OR REPLACE VIEW v_employee_directory AS
SELECT e.employee_id,
       e.employee_code,
       CONCAT(e.first_name, ' ', e.last_name) AS employee_name,
       e.email,
       e.job_title,
       d.department_name,
       l.location_name,
       e.is_active
FROM employees e
JOIN departments d ON d.department_id = e.department_id
JOIN locations l ON l.location_id = e.location_id;

SELECT * FROM v_employee_directory ORDER BY employee_id;

-- Analytical view with aggregation.
CREATE OR REPLACE VIEW v_project_financials AS
SELECT p.project_id,
       p.project_code,
       p.project_name,
       c.client_name,
       p.status,
       p.budget,
       COALESCE(SUM(CASE WHEN ex.status IN ('APPROVED','PAID') THEN ex.amount ELSE 0 END), 0) AS approved_expenses
FROM projects p
JOIN clients c ON c.client_id = p.client_id
LEFT JOIN expenses ex ON ex.project_id = p.project_id
GROUP BY p.project_id, p.project_code, p.project_name, c.client_name, p.status, p.budget;

SELECT * FROM v_project_financials ORDER BY approved_expenses DESC;

-- Inspect a view definition.
SHOW CREATE VIEW v_employee_directory;

-- ALTER VIEW can change the SELECT definition.
ALTER VIEW v_employee_directory AS
SELECT e.employee_id,
       e.employee_code,
       CONCAT(e.first_name, ' ', e.last_name) AS employee_name,
       e.email,
       e.job_title,
       d.department_name,
       l.location_name,
       e.is_active,
       e.hire_date
FROM employees e
JOIN departments d ON d.department_id = e.department_id
JOIN locations l ON l.location_id = e.location_id;

SELECT * FROM v_employee_directory LIMIT 5;

-- View with CHECK OPTION demonstration using a throwaway table.
CREATE TABLE view_demo_customers (
    id INT PRIMARY KEY AUTO_INCREMENT,
    name VARCHAR(100) NOT NULL,
    active BOOLEAN NOT NULL DEFAULT TRUE
);
INSERT INTO view_demo_customers (name, active) VALUES ('Demo A', TRUE), ('Demo B', FALSE);
CREATE OR REPLACE VIEW v_active_demo_customers AS
SELECT id, name, active
FROM view_demo_customers
WHERE active = TRUE
WITH CHECK OPTION;

-- This update succeeds because it keeps the row inside the view predicate.
UPDATE v_active_demo_customers
SET name = 'Demo A Updated'
WHERE id = 1;

-- This would fail with CHECK OPTION because the row would cease to qualify.
-- UPDATE v_active_demo_customers SET active = FALSE WHERE id = 1;

DROP VIEW v_active_demo_customers;
DROP TABLE view_demo_customers;

-- Drop a view when no longer needed.
DROP VIEW v_project_financials;

-- ============================================================================
-- 14. TEMPORARY TABLES + CREATE TABLE ... SELECT + TABLE / VALUES
-- ============================================================================

-- TEMPORARY TABLE exists only for the current session.
DROP TEMPORARY TABLE IF EXISTS tmp_high_value_orders;

CREATE TEMPORARY TABLE tmp_high_value_orders AS
SELECT o.order_id,
       o.order_number,
       o.customer_id,
       o.total_amount
FROM orders o
WHERE o.total_amount > 100000;

SELECT * FROM tmp_high_value_orders ORDER BY total_amount DESC;

-- Add an index to a temporary table, just as you would for repeated lookups.
ALTER TABLE tmp_high_value_orders
    ADD PRIMARY KEY (order_id);

-- TABLE is shorthand for returning all rows/columns from a table.
TABLE tmp_high_value_orders;

-- VALUES is a table-value constructor and can be used as a query source in MySQL 8.x.
VALUES ROW(1, 'Beginner'), ROW(2, 'Intermediate'), ROW(3, 'Advanced');

DROP TEMPORARY TABLE tmp_high_value_orders;

-- CREATE TABLE ... SELECT creates a table from a query result.
DROP TABLE IF EXISTS customer_revenue_snapshot;
CREATE TABLE customer_revenue_snapshot AS
SELECT c.customer_id,
       CONCAT(c.first_name, ' ', c.last_name) AS customer_name,
       COALESCE(SUM(CASE WHEN o.status <> 'CANCELLED' THEN o.total_amount ELSE 0 END), 0) AS revenue
FROM customers c
LEFT JOIN orders o ON o.customer_id = c.customer_id
GROUP BY c.customer_id, customer_name;

SELECT * FROM customer_revenue_snapshot ORDER BY revenue DESC;

-- This snapshot is intentionally temporary from a learning perspective.
DROP TABLE customer_revenue_snapshot;

-- ============================================================================
-- 15. TRANSACTIONS / SAVEPOINTS / LOCKING / ISOLATION
-- ============================================================================

-- Transaction basics: all changes are committed together.
START TRANSACTION;

UPDATE inventory
SET quantity = quantity - 1,
    reserved_quantity = reserved_quantity + 1
WHERE warehouse_id = 1
  AND product_id = 1
  AND quantity > reserved_quantity;

-- Check the affected row inside the transaction.
SELECT * FROM inventory WHERE warehouse_id = 1 AND product_id = 1;

COMMIT;

-- SAVEPOINT allows partial rollback inside a transaction.
START TRANSACTION;

UPDATE customers
SET loyalty_tier = 'PLATINUM'
WHERE customer_id = 2;

SAVEPOINT before_second_change;

UPDATE customers
SET loyalty_tier = 'GOLD'
WHERE customer_id = 3;

-- Undo only the second update.
ROLLBACK TO SAVEPOINT before_second_change;

-- Release the savepoint, then commit the first update.
RELEASE SAVEPOINT before_second_change;
COMMIT;

-- Revert the educational change so later data remains predictable.
UPDATE customers
SET loyalty_tier = 'SILVER'
WHERE customer_id = 2;

-- Test full rollback.
START TRANSACTION;
UPDATE products SET unit_price = unit_price + 999999 WHERE product_id = 1;
SELECT product_id, unit_price FROM products WHERE product_id = 1;
ROLLBACK;
SELECT product_id, unit_price FROM products WHERE product_id = 1;

-- SET TRANSACTION controls transaction characteristics. This affects the current session/next transaction.
SET SESSION TRANSACTION ISOLATION LEVEL READ COMMITTED;

START TRANSACTION;
SELECT @@transaction_isolation AS current_isolation_level;
COMMIT;

-- Set it back to the default commonly used by MySQL/InnoDB.
SET SESSION TRANSACTION ISOLATION LEVEL REPEATABLE READ;

-- SELECT ... FOR UPDATE locks selected InnoDB rows until the transaction ends.
START TRANSACTION;
SELECT product_id, quantity
FROM inventory
WHERE warehouse_id = 1 AND product_id = 1
FOR UPDATE;

-- Simulate a controlled stock reservation while holding the row lock.
UPDATE inventory
SET reserved_quantity = reserved_quantity + 1
WHERE warehouse_id = 1 AND product_id = 1
  AND reserved_quantity < quantity;
COMMIT;

-- SELECT ... FOR SHARE obtains shared locks on selected rows.
START TRANSACTION;
SELECT customer_id, loyalty_tier
FROM customers
WHERE customer_id = 1
FOR SHARE;
COMMIT;

-- NOWAIT / SKIP LOCKED are useful in concurrent worker patterns.
-- They are demonstrated as syntax examples; behavior depends on another session holding a lock.
START TRANSACTION;
SELECT product_id, quantity
FROM inventory
WHERE warehouse_id = 1
FOR UPDATE SKIP LOCKED;
ROLLBACK;

-- ============================================================================
-- 16. STORED PROCEDURES + STORED FUNCTION
-- ============================================================================

DELIMITER $$

-- Procedure with input parameter and result set.
DROP PROCEDURE IF EXISTS sp_employee_summary$$
CREATE PROCEDURE sp_employee_summary(IN p_employee_id INT UNSIGNED)
BEGIN
    SELECT e.employee_id,
           CONCAT(e.first_name, ' ', e.last_name) AS employee_name,
           e.job_title,
           d.department_name,
           e.current_salary,
           COALESCE(SUM(ep.allocation_percent), 0) AS total_project_allocation
    FROM employees e
    JOIN departments d ON d.department_id = e.department_id
    LEFT JOIN employee_projects ep ON ep.employee_id = e.employee_id
    WHERE e.employee_id = p_employee_id
    GROUP BY e.employee_id, employee_name, e.job_title, d.department_name, e.current_salary;
END$$

-- Call the procedure.
CALL sp_employee_summary(6)$$

-- Scalar stored function.
DROP FUNCTION IF EXISTS fn_annual_to_monthly_salary$$
CREATE FUNCTION fn_annual_to_monthly_salary(p_annual_salary DECIMAL(12,2))
RETURNS DECIMAL(12,2)
DETERMINISTIC
RETURN ROUND(p_annual_salary / 12, 2)$$

-- Use the function in a query.
SELECT employee_id,
       first_name,
       current_salary,
       fn_annual_to_monthly_salary(current_salary) AS monthly_salary
FROM employees
ORDER BY current_salary DESC$$

-- Procedure with INOUT parameter.
DROP PROCEDURE IF EXISTS sp_apply_discount$$
CREATE PROCEDURE sp_apply_discount(
    IN p_amount DECIMAL(12,2),
    IN p_discount_percent DECIMAL(5,2),
    INOUT p_final_amount DECIMAL(12,2)
)
BEGIN
    SET p_final_amount = ROUND(
        p_amount * (1 - p_discount_percent / 100),
        2
    );
END$$

SET @final_amount = 1000.00$$
CALL sp_apply_discount(1000.00, 15.00, @final_amount)$$
SELECT @final_amount AS final_amount$$

-- Procedure with local variables, conditional logic, transaction and output.
DROP PROCEDURE IF EXISTS sp_create_payroll$$
CREATE PROCEDURE sp_create_payroll(
    IN p_payroll_month DATE,
    IN p_tax_rate DECIMAL(5,2)
)
BEGIN
    START TRANSACTION;

    INSERT INTO payroll_records (employee_id, payroll_month, gross_salary, tax_amount, net_salary)
    SELECT employee_id,
           p_payroll_month,
           ROUND(current_salary / 12, 2),
           ROUND((current_salary / 12) * p_tax_rate / 100, 2),
           ROUND((current_salary / 12) * (1 - p_tax_rate / 100), 2)
    FROM employees
    WHERE is_active = TRUE
    ON DUPLICATE KEY UPDATE
        gross_salary = VALUES(gross_salary),
        tax_amount = VALUES(tax_amount),
        net_salary = VALUES(net_salary),
        processed_at = CURRENT_TIMESTAMP;

    COMMIT;

    SELECT COUNT(*) AS payroll_rows_for_month
    FROM payroll_records
    WHERE payroll_month = p_payroll_month;
END$$

CALL sp_create_payroll('2026-10-01', 20.00)$$

DELIMITER ;

-- Show stored program metadata.
SHOW PROCEDURE STATUS WHERE Db = DATABASE();
SHOW FUNCTION STATUS WHERE Db = DATABASE();

-- ============================================================================
-- 17. TRIGGERS + AUDIT TRAIL
-- ============================================================================

DELIMITER $$

-- Audit salary changes automatically whenever current_salary changes.
DROP TRIGGER IF EXISTS trg_employee_salary_audit$$
CREATE TRIGGER trg_employee_salary_audit
AFTER UPDATE ON employees
FOR EACH ROW
BEGIN
    IF OLD.current_salary <> NEW.current_salary THEN
        INSERT INTO employee_audit (
            employee_id,
            action_type,
            old_salary,
            new_salary,
            details
        ) VALUES (
            NEW.employee_id,
            'SALARY_CHANGE',
            OLD.current_salary,
            NEW.current_salary,
            JSON_OBJECT(
                'old_job_title', OLD.job_title,
                'new_job_title', NEW.job_title,
                'changed_by_connection', CONNECTION_ID()
            )
        );
    END IF;
END$$

-- Maintain orders.subtotal/discount/tax/total after an order item is inserted.
DROP TRIGGER IF EXISTS trg_order_item_after_insert$$
CREATE TRIGGER trg_order_item_after_insert
AFTER INSERT ON order_items
FOR EACH ROW
BEGIN
    UPDATE orders o
    SET o.subtotal = (
            SELECT COALESCE(SUM(quantity * unit_price), 0)
            FROM order_items
            WHERE order_id = NEW.order_id
        ),
        o.discount_amount = (
            SELECT COALESCE(SUM(quantity * unit_price - line_total), 0)
            FROM order_items
            WHERE order_id = NEW.order_id
        ),
        o.tax_amount = ROUND((
            SELECT COALESCE(SUM(line_total), 0)
            FROM order_items
            WHERE order_id = NEW.order_id
        ) * 0.18, 2),
        o.total_amount = ROUND((
            SELECT COALESCE(SUM(line_total), 0)
            FROM order_items
            WHERE order_id = NEW.order_id
        ) * 1.18, 2)
    WHERE o.order_id = NEW.order_id;
END$$

DROP TRIGGER IF EXISTS trg_order_item_after_update$$
CREATE TRIGGER trg_order_item_after_update
AFTER UPDATE ON order_items
FOR EACH ROW
BEGIN
    UPDATE orders o
    SET o.subtotal = (
            SELECT COALESCE(SUM(quantity * unit_price), 0)
            FROM order_items
            WHERE order_id = NEW.order_id
        ),
        o.discount_amount = (
            SELECT COALESCE(SUM(quantity * unit_price - line_total), 0)
            FROM order_items
            WHERE order_id = NEW.order_id
        ),
        o.tax_amount = ROUND((
            SELECT COALESCE(SUM(line_total), 0)
            FROM order_items
            WHERE order_id = NEW.order_id
        ) * 0.18, 2),
        o.total_amount = ROUND((
            SELECT COALESCE(SUM(line_total), 0)
            FROM order_items
            WHERE order_id = NEW.order_id
        ) * 1.18, 2)
    WHERE o.order_id = NEW.order_id;

    -- If the item was moved to another order (possible if the FK values are changed),
    -- also recalculate the old order.
    IF OLD.order_id <> NEW.order_id THEN
        UPDATE orders o
        SET o.subtotal = (
                SELECT COALESCE(SUM(quantity * unit_price), 0)
                FROM order_items
                WHERE order_id = OLD.order_id
            ),
            o.discount_amount = (
                SELECT COALESCE(SUM(quantity * unit_price - line_total), 0)
                FROM order_items
                WHERE order_id = OLD.order_id
            ),
            o.tax_amount = ROUND((
                SELECT COALESCE(SUM(line_total), 0)
                FROM order_items
                WHERE order_id = OLD.order_id
            ) * 0.18, 2),
            o.total_amount = ROUND((
                SELECT COALESCE(SUM(line_total), 0)
                FROM order_items
                WHERE order_id = OLD.order_id
            ) * 1.18, 2)
        WHERE o.order_id = OLD.order_id;
    END IF;
END$$

DROP TRIGGER IF EXISTS trg_order_item_after_delete$$
CREATE TRIGGER trg_order_item_after_delete
AFTER DELETE ON order_items
FOR EACH ROW
BEGIN
    UPDATE orders o
    SET o.subtotal = (
            SELECT COALESCE(SUM(quantity * unit_price), 0)
            FROM order_items
            WHERE order_id = OLD.order_id
        ),
        o.discount_amount = (
            SELECT COALESCE(SUM(quantity * unit_price - line_total), 0)
            FROM order_items
            WHERE order_id = OLD.order_id
        ),
        o.tax_amount = ROUND((
            SELECT COALESCE(SUM(line_total), 0)
            FROM order_items
            WHERE order_id = OLD.order_id
        ) * 0.18, 2),
        o.total_amount = ROUND((
            SELECT COALESCE(SUM(line_total), 0)
            FROM order_items
            WHERE order_id = OLD.order_id
        ) * 1.18, 2)
    WHERE o.order_id = OLD.order_id;
END$$

DELIMITER ;

-- Trigger test: change a salary and inspect the generated audit row.
UPDATE employees
SET current_salary = current_salary + 1000
WHERE employee_id = 13;

SELECT *
FROM employee_audit
WHERE employee_id = 13
ORDER BY audit_id DESC;

-- Trigger test on order items, inside a transaction so the test data can be reverted.
START TRANSACTION;
INSERT INTO order_items (order_id, product_id, quantity, unit_price, discount_percent)
VALUES (10, 8, 1, 12500.00, 0.00);

SELECT order_number, subtotal, discount_amount, tax_amount, total_amount
FROM orders
WHERE order_id = 10;

ROLLBACK;

-- ============================================================================
-- 18. EVENTS
-- ============================================================================

-- EVENT scheduler status. CREATE EVENT can succeed while the scheduler is OFF,
-- but an OFF scheduler means the event will not execute automatically.
SHOW VARIABLES LIKE 'event_scheduler';

-- OPTIONAL: requires the EVENT privilege. Enable for the server/session according to
-- your environment's policy. On managed databases, this may not be permitted.
-- SET GLOBAL event_scheduler = ON;

DELIMITER $$

DROP EVENT IF EXISTS ev_daily_audit_marker$$
CREATE EVENT ev_daily_audit_marker
ON SCHEDULE EVERY 1 DAY
STARTS CURRENT_TIMESTAMP + INTERVAL 1 DAY
DO
BEGIN
    INSERT INTO employee_audit (employee_id, action_type, details)
    VALUES (1, 'DAILY_EVENT_HEARTBEAT', JSON_OBJECT('source', 'MySQL EVENT'));
END$$

DELIMITER ;

-- Inspect scheduled events.
SHOW EVENTS;

-- ============================================================================
-- 19. PREPARED STATEMENTS / DYNAMIC SQL
-- ============================================================================

-- Prepared statements prevent the SQL text itself from changing while values vary.
SET @min_salary = 90000.00;

PREPARE stmt_employee_search
FROM 'SELECT employee_id, first_name, last_name, current_salary
      FROM employees
      WHERE current_salary >= ?
      ORDER BY current_salary DESC';

EXECUTE stmt_employee_search USING @min_salary;
DEALLOCATE PREPARE stmt_employee_search;

-- Dynamic SQL can safely parameterize values, but identifiers require building SQL text.
SET @table_name = 'employees';
SET @sql = CONCAT('SELECT COUNT(*) AS row_count FROM ', QUOTE(@table_name));

-- The following demonstrates PREPARE mechanics. QUOTE() is for strings; do not
-- treat it as a general-purpose identifier-quoting function. For production dynamic
-- identifiers, whitelist allowed table/column names in application logic.
SET @sql = 'SELECT COUNT(*) AS employee_count FROM employees';
PREPARE stmt_dynamic FROM @sql;
EXECUTE stmt_dynamic;
DEALLOCATE PREPARE stmt_dynamic;

-- ============================================================================
-- 20. INDEXES / EXPLAIN / OPTIMIZER INSPECTION
-- ============================================================================

-- Existing indexes can be inspected before deciding to add more.
SHOW INDEX FROM orders;
SHOW INDEX FROM order_items;

-- EXPLAIN shows the optimizer's intended execution plan.
EXPLAIN
SELECT o.order_id, o.order_number, o.total_amount
FROM orders o
WHERE o.customer_id = 1
  AND o.status = 'COMPLETED'
ORDER BY o.order_date DESC;

-- Add a composite index matching a common filter + ordering pattern.
CREATE INDEX idx_orders_customer_status_date
ON orders (customer_id, status, order_date DESC);

-- Re-run EXPLAIN and compare key/key_len/rows/Extra with the previous plan.
EXPLAIN
SELECT o.order_id, o.order_number, o.total_amount
FROM orders o
WHERE o.customer_id = 1
  AND o.status = 'COMPLETED'
ORDER BY o.order_date DESC;

-- EXPLAIN FORMAT=JSON exposes optimizer information as JSON.
EXPLAIN FORMAT=JSON
SELECT o.order_number, c.email, o.total_amount
FROM orders o
JOIN customers c ON c.customer_id = o.customer_id
WHERE o.total_amount > 100000;

-- ANALYZE gives actual execution statistics and can help validate assumptions.
-- The exact output varies by MySQL version and data distribution.
EXPLAIN ANALYZE
SELECT o.order_number, c.email, o.total_amount
FROM orders o
JOIN customers c ON c.customer_id = o.customer_id
WHERE o.total_amount > 100000;

-- Create an index on a generated JSON-extraction column through an explicit helper column.
-- This pattern is useful when a JSON attribute is frequently filtered.
ALTER TABLE products
    ADD COLUMN json_storage_gb INT
        GENERATED ALWAYS AS (CAST(JSON_UNQUOTE(attributes->'$.storage_gb') AS UNSIGNED)) STORED;

CREATE INDEX idx_products_json_storage_gb
    ON products (json_storage_gb);

SELECT product_name, json_storage_gb
FROM products
WHERE json_storage_gb >= 512
ORDER BY json_storage_gb DESC;

-- MySQL supports functional index expressions as well. Demonstrate one on a throwaway table.
CREATE TABLE functional_index_demo (
    id INT PRIMARY KEY AUTO_INCREMENT,
    email VARCHAR(255) NOT NULL
);
INSERT INTO functional_index_demo (email) VALUES
('Alice@Example.com'), ('Bob@Example.com'), ('carol@example.com');

CREATE INDEX idx_lower_email
ON functional_index_demo ((LOWER(email)));

EXPLAIN SELECT *
FROM functional_index_demo
WHERE LOWER(email) = 'alice@example.com';

DROP TABLE functional_index_demo;

-- ============================================================================
-- 21. ADVANCED DML PATTERNS
-- ============================================================================

-- Update only the latest salary-history row per employee using a window function in a CTE.
WITH ranked_history AS (
    SELECT salary_history_id,
           ROW_NUMBER() OVER (
               PARTITION BY employee_id
               ORDER BY effective_from DESC
           ) AS rn
    FROM salary_history
)
UPDATE salary_history sh
JOIN ranked_history rh ON rh.salary_history_id = sh.salary_history_id
SET sh.change_reason = CONCAT(sh.change_reason, ' (latest)')
WHERE rh.rn = 1;

-- DELETE using a CTE-derived result. Wrapped in a transaction and rolled back.
START TRANSACTION;
WITH old_expenses AS (
    SELECT expense_id
    FROM expenses
    WHERE expense_date < '2026-01-01'
)
DELETE e
FROM expenses e
JOIN old_expenses oe ON oe.expense_id = e.expense_id;
ROLLBACK;

-- INSERT from multiple joined tables.
DROP TABLE IF EXISTS active_project_members_snapshot;
CREATE TABLE active_project_members_snapshot (
    employee_id INT UNSIGNED NOT NULL,
    employee_name VARCHAR(121) NOT NULL,
    project_name VARCHAR(150) NOT NULL,
    captured_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

INSERT INTO active_project_members_snapshot (employee_id, employee_name, project_name)
SELECT e.employee_id,
       CONCAT(e.first_name, ' ', e.last_name),
       p.project_name
FROM employees e
JOIN employee_projects ep ON ep.employee_id = e.employee_id
JOIN projects p ON p.project_id = ep.project_id
WHERE p.status = 'ACTIVE';

SELECT * FROM active_project_members_snapshot ORDER BY project_name, employee_id;
DROP TABLE active_project_members_snapshot;

-- INSERT with a derived date and calculation.
INSERT INTO payroll_records (employee_id, payroll_month, gross_salary, tax_amount, net_salary)
SELECT 1,
       '2026-11-01',
       fn_annual_to_monthly_salary((SELECT current_salary FROM employees WHERE employee_id = 1)),
       ROUND(fn_annual_to_monthly_salary((SELECT current_salary FROM employees WHERE employee_id = 1)) * 0.20, 2),
       ROUND(fn_annual_to_monthly_salary((SELECT current_salary FROM employees WHERE employee_id = 1)) * 0.80, 2)
ON DUPLICATE KEY UPDATE
    gross_salary = VALUES(gross_salary),
    tax_amount = VALUES(tax_amount),
    net_salary = VALUES(net_salary);

-- ============================================================================
-- 22. DATA QUALITY / CONSTRAINT LABS
-- ============================================================================

-- Test UNIQUE constraint safely inside a transaction. This statement is intentionally
-- commented out because an actual duplicate would abort in strict mode.
-- INSERT INTO employees (employee_code, first_name, last_name, email, department_id,
--     location_id, job_title, hire_date, current_salary)
-- VALUES ('E001', 'Duplicate', 'User', 'duplicate@example.com', 1, 1,
--     'Engineer', '2026-01-01', 50000);

-- Test CHECK constraints conceptually. Uncomment one at a time to observe the error.
-- INSERT INTO products (sku, product_name, category, unit_price, cost_price, stock_reorder_level)
-- VALUES ('BAD-001', 'Invalid Product', 'Test', 100, 150, 10);

-- INFORMATION_SCHEMA can be used to inventory constraints and indexes.
SELECT constraint_name, table_name, constraint_type
FROM information_schema.table_constraints
WHERE constraint_schema = DATABASE()
ORDER BY table_name, constraint_type, constraint_name;

-- Find orphan-style conditions using LEFT JOIN checks.
SELECT ep.employee_id, ep.project_id
FROM employee_projects ep
LEFT JOIN employees e ON e.employee_id = ep.employee_id
LEFT JOIN projects p ON p.project_id = ep.project_id
WHERE e.employee_id IS NULL OR p.project_id IS NULL;

-- Detect duplicate business values before adding a UNIQUE constraint.
SELECT email, COUNT(*) AS occurrences
FROM customers
GROUP BY email
HAVING COUNT(*) > 1;

-- Check negative/invalid financial values with validation queries.
SELECT * FROM products WHERE unit_price < cost_price;
SELECT * FROM inventory WHERE reserved_quantity > quantity;
SELECT * FROM projects WHERE end_date IS NOT NULL AND end_date < start_date;

-- ============================================================================
-- 23. OPTIONAL ADMINISTRATION: USERS / ROLES / GRANTS
-- ============================================================================
-- This section is intentionally commented out. CREATE USER/GRANT/ROLE requires
-- account-management privileges and should not be executed blindly in shared DBs.
-- The syntax below is valid MySQL 8.x learning material.
--
-- CREATE ROLE 'reporting_role';
-- GRANT SELECT ON mysql_mastery_lab.* TO 'reporting_role';
-- CREATE USER 'reporting_user'@'localhost' IDENTIFIED BY 'ChangeThisPassword!';
-- GRANT 'reporting_role' TO 'reporting_user'@'localhost';
-- SET DEFAULT ROLE 'reporting_role' TO 'reporting_user'@'localhost';
-- SHOW GRANTS FOR 'reporting_user'@'localhost';
-- REVOKE SELECT ON mysql_mastery_lab.* FROM 'reporting_role';
-- DROP USER 'reporting_user'@'localhost';
-- DROP ROLE 'reporting_role';

-- ============================================================================
-- 24. CAPSTONE CHALLENGES
-- ============================================================================
-- These are deliberately provided WITHOUT solutions. Solve them after completing
-- the earlier sections. The database contains enough data to produce meaningful
-- answers.

-- Challenge 1:
-- Find the top 3 highest-paid active employees in each department.

-- Challenge 2:
-- Find departments whose average salary is above the company average salary.

-- Challenge 3:
-- Find customers whose total non-cancelled spend is above the average customer spend.

-- Challenge 4:
-- Return each customer's first order date, latest order date, order count,
-- and total spend.

-- Challenge 5:
-- Find products that have never appeared in a non-cancelled order.

-- Challenge 6:
-- Find the most profitable product category using unit_price - cost_price times
-- quantity sold in non-cancelled orders.

-- Challenge 7:
-- Rank sales employees by monthly non-cancelled revenue and show month-over-month
-- revenue change with LAG().

-- Challenge 8:
-- Find employees whose salary is higher than their manager's salary.

-- Challenge 9:
-- Using a recursive CTE, return every employee's management depth and full chain
-- from the top-level manager.

-- Challenge 10:
-- Find projects where approved expenses exceed 10% of project budget.

-- Challenge 11:
-- Find the warehouse/product combinations that are below their reorder level.

-- Challenge 12:
-- Find customers who bought from at least three distinct product categories.

-- Challenge 13:
-- Find the second-highest-paid employee in every department, handling ties correctly.

-- Challenge 14:
-- Calculate a 3-order moving average of revenue per salesperson.

-- Challenge 15:
-- Return the most recent salary-history row for every employee without using MAX()
-- in the SELECT list.

-- Challenge 16:
-- Find projects with no timesheet entries at all.

-- Challenge 17:
-- Find employees who have every one of the three core skills: SQL, Python, and
-- JavaScript (use relational division patterns such as GROUP BY/HAVING or NOT EXISTS).

-- Challenge 18:
-- Produce a monthly revenue report with months that have no orders included as
-- zero values (use the recursive month CTE pattern).

-- Challenge 19:
-- Use JSON_TABLE to list every employee language as one row per language.

-- Challenge 20:
-- Explain and optimize a deliberately slow query using EXPLAIN ANALYZE, then
-- compare the plan before and after adding the most appropriate index.

-- ============================================================================
-- 25. CLEANUP LAB
-- ============================================================================
-- Leave this section commented while learning. When you are completely finished,
-- you can run it to remove the database and start from scratch.
--
-- DROP DATABASE mysql_mastery_lab;
-- ============================================================================
