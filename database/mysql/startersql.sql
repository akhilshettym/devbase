-- ==============================================================================
-- DATABASE & INITIAL TABLE SETUP
-- ==============================================================================

-- Create the database if needed (uncomment to run)
-- CREATE DATABASE startersql;

-- Select and switch to the target database
USE startersql;

-- Create the initial 'users' table structure
CREATE TABLE users (
    id INT AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    email VARCHAR(100) UNIQUE NOT NULL,
    gender ENUM('MALE', 'FEMALE', 'OTHER'),
    date_of_birth DATE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- ==============================================================================
-- BASIC DATA RETRIEVAL (SELECT)
-- ==============================================================================

-- Retrieve all columns and rows from the users table
SELECT * FROM users;

-- Retrieve only specific columns (name and email) from the users table
SELECT name, email FROM users;

-- ==============================================================================
-- TABLE RENAMING OPERATIONS
-- ==============================================================================

-- Rename the table 'users' to 'programmers'
RENAME TABLE users to programmers;

-- Retrieve all records from the newly renamed 'programmers' table
SELECT * FROM programmers;

-- Rename the table back to 'users'
RENAME TABLE programmers to users;

-- Confirm table name was restored back to 'users'
SELECT * FROM users;

-- ==============================================================================
-- ALTER TABLE OPERATIONS (ADDING/DROPPING/REORDERING COLUMNS)
-- ==============================================================================

-- Add a new boolean column 'is_active' with a default value of true
ALTER TABLE users ADD COLUMN is_active BOOLEAN DEFAULT true;

-- Verify the new 'is_active' column addition
SELECT * FROM users;

-- Drop (remove) the 'is_active' column from the table
ALTER TABLE users DROP COLUMN is_active;

-- Verify column removal
SELECT * FROM users;

-- Modify the 'name' column length from 100 to 150 characters
ALTER TABLE users MODIFY COLUMN name VARCHAR(150);

-- Reposition the 'email' column to appear immediately after 'id'
ALTER TABLE users MODIFY COLUMN email VARCHAR(100) AFTER id;

-- Check layout after reordering 'email'
SELECT * FROM users;

-- Reposition the 'name' column to appear immediately after 'id'
ALTER TABLE users MODIFY COLUMN name VARCHAR(150) AFTER id;

-- Verify updated column layout
SELECT * FROM users;

-- ==============================================================================
-- SAMPLE DATA INSERTION (INDIVIDUAL & BULK)
-- ==============================================================================

-- Insert individual records using positional values matching the table schema
INSERT INTO users VALUES (1, "Akhil", "akhil@gmail.com", "MALE", "2003-03-29", DEFAULT);
INSERT INTO users VALUES (2, "Shetty", "shetty@gmail.com", "MALE", "2003-03-30", DEFAULT);
INSERT INTO users VALUES (3, "M", "m@gmail.com", "MALE", "2003-03-31", DEFAULT);
INSERT INTO users VALUES (4, "Akhil", "akhi@gmail.com", "MALE", "2003-03-31", DEFAULT);

-- Insert multiple records in a single statement (Bulk Insert)
INSERT INTO users VALUES 
(1, "Akhil", "akhil@gmail.com", "MALE", "2003-03-29", DEFAULT),
(2, "Shetty", "shetty@gmail.com", "MALE", "2003-03-30", DEFAULT),
(3, "M", "m@gmail.com", "MALE", "2003-03-31", DEFAULT),
(4, "Akhil", "akhi@gmail.com", "MALE", "2003-03-31", DEFAULT);

-- View inserted data
SELECT * FROM users;

-- ==============================================================================
-- SCHEMA MODIFICATIONS & DATA DELETION
-- ==============================================================================

-- Add a 'salary' column to store monetary values
ALTER TABLE users ADD COLUMN salary DECIMAL(10, 2);

-- Delete the record where 'id' equals 1
DELETE FROM users WHERE id = 1;

-- Increase 'salary' column precision and reposition it after 'date_of_birth'
ALTER TABLE users MODIFY COLUMN salary DECIMAL(20, 2) AFTER date_of_birth;

-- View table data and column layout after modification
SELECT * FROM users;

-- ==============================================================================
-- DROPPING & RE-CREATING TABLE
-- ==============================================================================

-- Permanently delete the 'users' table and all its data
DROP TABLE users;

-- Attempting to query a dropped table (Will throw Error 1146: Table doesn't exist)
SELECT * FROM users;

-- Re-create the 'users' table schema with the 'salary' column included
CREATE TABLE users (
    id INT AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    email VARCHAR(100) UNIQUE NOT NULL,
    gender ENUM('MALE', 'FEMALE', 'OTHER'),
    date_of_birth DATE,
    salary DECIMAL(10, 2),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- ==============================================================================
-- SEED DATA INSERTION (20 DUMMY RECORDS)
-- ==============================================================================

-- Insert 20 dummy records specifying explicit target columns
INSERT INTO users (name, email, gender, date_of_birth, salary) VALUES 
('Aarav Sharma', 'aarav.sharma@example.com', 'MALE', '1995-04-12', 65000.00),
('Priya Patel', 'priya.patel@example.com', 'FEMALE', '1998-08-23', 72000.00),
('Rohan Mehta', 'rohan.mehta@example.com', 'MALE', '1992-11-05', 85000.00),
('Ananya Iyer', 'ananya.iyer@example.com', 'FEMALE', '2001-01-15', 55000.00),
('Vikram Singh', 'vikram.singh@example.com', 'MALE', '1988-06-30', 95000.00),
('Sneha Rao', 'sneha.rao@example.com', 'FEMALE', '1996-09-18', 68000.00),
('Rahul Nair', 'rahul.nair@example.com', 'MALE', '1994-03-22', 78000.00),
('Pooja Verma', 'pooja.verma@example.com', 'FEMALE', '1999-12-10', 60000.00),
('Karan Kapoor', 'karan.kapoor@example.com', 'MALE', '1990-07-04', 90000.00),
('Neha Gupta', 'neha.gupta@example.com', 'FEMALE', '1997-05-14', 71000.00),
('Siddharth Joshi', 'siddharth.j@example.com', 'MALE', '1993-02-28', 82000.00),
('Kavya Deshmukh', 'kavya.d@example.com', 'FEMALE', '2000-10-08', 58000.00),
('Aditya Reddy', 'aditya.reddy@example.com', 'MALE', '1991-12-19', 88000.00),
('Riya Sen', 'riya.sen@example.com', 'FEMALE', '1995-07-25', 67000.00),
('Amit Kumar', 'amit.kumar@example.com', 'MALE', '1987-09-11', 105000.00),
('Divya Agarwal', 'divya.a@example.com', 'FEMALE', '1996-04-03', 74000.00),
('Varun Malhotra', 'varun.m@example.com', 'MALE', '1998-11-27', 63000.00),
('Meera Chatterjee', 'meera.c@example.com', 'FEMALE', '1994-08-16', 79000.00),
('Arjun Saxena', 'arjun.s@example.com', 'MALE', '2002-05-20', 52000.00),
('Shreya Das', 'shreya.das@example.com', 'FEMALE', '1997-01-31', 70000.00);

-- ==============================================================================
-- BASIC SELECTION & FILTERING
-- ==============================================================================

-- Retrieve all rows and columns from the users table
SELECT * FROM users;

-- Retrieve specific columns (name, gender, salary)
SELECT name, gender, salary FROM users;

-- Filter records where gender matches 'MALE'
SELECT name, gender, salary FROM users WHERE gender="male";

-- Alternative syntax examples for inequality operators (!= and <>)
-- SELECT name, gender, salary FROM users WHERE gender!="male";
-- SELECT name, gender, salary FROM users WHERE gender<>"male";

-- Filter records with date of birth before September 9, 1995
SELECT * FROM users WHERE date_of_birth < "1995-09-09";

-- Filter records where user ID is less than or equal to 10
SELECT * FROM users WHERE id <= 10;

-- Retrieve records where date of birth is missing (NULL)
SELECT * FROM users WHERE date_of_birth IS NULL;

-- Retrieve records where date of birth is populated (NOT NULL)
SELECT * FROM users WHERE date_of_birth IS NOT NULL;

-- Retrieve records born within a date range (inclusive)
SELECT * FROM users WHERE date_of_birth BETWEEN "1990-09-09" AND "1995-09-09";

-- Filter records matching any value within the specified set
SELECT * FROM users WHERE gender IN ("MALE", "FEMALE");

-- ==============================================================================
-- LOGICAL OPERATORS, SORTING & PAGINATION
-- ==============================================================================

-- Filter records matching BOTH conditions (Female AND Salary > 70000)
SELECT * FROM users WHERE gender = "FEMALE" AND salary > "70000";

-- Filter records matching EITHER condition (Male OR Salary > 65000)
SELECT * FROM users WHERE gender = "MALE" OR salary > "65000";

-- Filter records with OR logic and sort results by date of birth in ascending order (oldest first)
SELECT * FROM users WHERE gender = "MALE" OR salary > "65000" ORDER BY date_of_birth ASC;

-- Filter, sort ascending by birth date, and limit output to the first 5 records
SELECT * FROM users WHERE gender = "MALE" OR salary > "65000" ORDER BY date_of_birth ASC LIMIT 5;

-- Get the 5 newest created users earning more than 60,000
SELECT * FROM users WHERE salary > 60000 ORDER BY created_at DESC LIMIT 5;

-- Retrieve all users sorted by salary in descending order (highest to lowest)
SELECT * FROM users ORDER BY salary DESC;

-- Filter records with salary within a numeric range (50000 to 70000 inclusive)
SELECT * FROM users WHERE salary BETWEEN 50000 AND 70000;

-- ==============================================================================
-- DATA MODIFICATION (UPDATE & DELETE)
-- ==============================================================================

-- Check table data prior to modifications
SELECT * FROM users;

-- Update salary for a specific user ID
UPDATE users SET salary = 45000 WHERE id = 2;

-- Update multiple columns (salary and email) for a specific user ID
UPDATE users SET salary = 70000, email = "aarav.sharma@gmail.com" WHERE id = 1;

-- Update salary for user ID 5
UPDATE users SET salary = 70000 WHERE id = 5;

-- Relative update: Increase salary by 10,000 for users earning under 60,000
UPDATE users SET salary = salary + 10000 WHERE salary < 60000;

-- Update gender attribute by matching user name
UPDATE users SET gender = "OTHER" WHERE name = "Priya Patel";

-- Preview records that meet the deletion criteria
SELECT * FROM users WHERE salary <= 55000;

-- Delete records where salary is less than or equal to 55,000
DELETE FROM users WHERE salary <= 55000;

-- Danger: Commented command to delete table and all data permanently
-- DROP TABLE users;

-- Verify table data after deletion operations
SELECT * FROM users;

-- ==============================================================================
-- TABLE CONSTRAINTS
-- ==============================================================================

-- Add a UNIQUE constraint to ensure no duplicate email addresses (Commented)
-- ALTER TABLE users ADD CONSTRAINT unique_email UNIQUE (email);

-- Add a CHECK constraint ensuring date of birth is after January 1, 1920
ALTER TABLE users ADD CONSTRAINT check_dob CHECK (date_of_birth > "1920-01-01");

-- ==============================================================================
-- AGGREGATE FUNCTIONS & GROUPING
-- ==============================================================================

-- Count total number of rows in the table
SELECT COUNT(*) FROM users;

-- Count total number of male users
SELECT COUNT(*) FROM users WHERE gender = "MALE";

-- Find the lowest and highest salary values
SELECT MIN(salary) AS min_salary, MAX(salary) AS max_salary FROM users;

-- Calculate total sum of all user salaries
SELECT SUM(salary) AS total FROM users;

-- Calculate overall average salary
SELECT AVG(salary) AS avg_salary FROM users;

-- Calculate average salary broken down by gender category
SELECT gender, AVG(salary) AS avg_salary FROM users GROUP BY gender;

-- ==============================================================================
-- BUILT-IN SCALAR FUNCTIONS (STRING, DATE, NUMERIC, CONDITIONAL)
-- ==============================================================================

-- String Function: Calculate character length of names
SELECT id, name, LENGTH(name) AS name_len FROM users;

-- String Function: Convert name to lowercase and compute length
SELECT id, LOWER(name) AS lower, LENGTH(name) AS name_len FROM users;

-- String Function: Combine text (lowercase name) and number (id) into a single string
SELECT id, LOWER(name) AS lower, CONCAT(LOWER(name), id), LENGTH(name) AS name_len FROM users;

-- Display name and string length
SELECT name, LENGTH(name) AS name_len FROM users;

-- Date Function: Calculate difference in days between current date and birth date
SELECT name, DATEDIFF(CURDATE(), date_of_birth) AS days FROM users;

-- Math Functions: Demonstrate standard rounding, rounding down (FLOOR), and rounding up (CEIL)
SELECT salary, ROUND(salary) AS rounded, FLOOR(salary) AS floored, CEIL(salary) AS ceiled FROM users;

-- Math Function: Modulo operator to find remainder when dividing ID by 2 (Even/Odd test)
SELECT id, MOD(id, 2) AS remainder FROM users;

-- Conditional Function: Evaluates condition and returns "YES" if female, otherwise "NO"
SELECT name, gender, IF(gender = "FEMALE", "YES", "NO") AS is_female FROM users;



