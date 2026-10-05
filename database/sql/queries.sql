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

-- ==============================================================================
-- TRANSACTION CONTROL (COMMIT & ROLLBACK)
-- ==============================================================================

-- Enable Autocommit mode (every individual SQL statement is committed automatically)
SET AUTOCOMMIT = 1;

-- Disable Autocommit mode (starts a manual transaction session where changes require explicitly calling COMMIT)
SET AUTOCOMMIT = 0;

-- Display current state of users before running transaction tests
SELECT * FROM users;

-- Delete user with ID 4 (this change remains temporary in current session)
DELETE FROM users WHERE id = 4;

-- Rollback the transaction to undo the deletion and restore the state to the previous COMMIT
ROLLBACK;

-- Delete user with ID 4 again
DELETE FROM users WHERE id = 4;

-- Permanently save and commit all changes made during this transaction
COMMIT;

-- ==============================================================================
-- FOREIGN KEYS & CHILD TABLE RELATIONSHIPS
-- ==============================================================================

-- Switch to active database
USE startersql;

-- Drop addresses table if it already exists to allow a clean creation
DROP TABLE IF EXISTS addresses;

-- Create addresses table with a foreign key referencing users table (with CASCADE delete)
CREATE TABLE addresses (
 id INT AUTO_INCREMENT PRIMARY KEY,
 user_id INT,
 street VARCHAR(255),
 city VARCHAR(100),
 state VARCHAR(100),
 pincode VARCHAR(10),
 CONSTRAINT fk_users FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);

-- Seed sample address records linked to existing user IDs
INSERT INTO addresses (id, user_id, street, city, state, pincode) VALUES
(1, 1, '102 Main Street', 'New York', 'NY', '10001'),
(2, 2, '456 Oak Avenue', 'Los Angeles', 'CA', '90001'),
(3, 3, '789 Pine Road', 'Chicago', 'IL', '60601'),
(4, 4, '321 Elm Lane', 'Houston', 'TX', '77001'),
(5, 5, '654 Maple Court', 'Phoenix', 'AZ', '85001'),
(6, 6, '987 Cedar Drive', 'Philadelphia', 'PA', '19101'),
(7, 7, '147 Birch Way', 'San Antonio', 'TX', '78201'),
(8, 8, '258 Walnut Street', 'San Diego', 'CA', '92101'),
(9, 9, '369 Ash Avenue', 'Dallas', 'TX', '75201'),
(10, 10, '741 Cherry Lane', 'San Jose', 'CA', '95101'),
(11, 11, '852 Willow Drive', 'Austin', 'TX', '78701'),
(12, 12, '963 Chestnut Court', 'Jacksonville', 'FL', '32201'),
(13, 13, '159 Poplar Road', 'Fort Worth', 'TX', '76101'),
(14, 14, '260 Redwood Lane', 'Columbus', 'OH', '43201'),
(15, 15, '370 Spruce Way', 'Charlotte', 'NC', '28201'),
(16, 16, '480 Magnolia Drive', 'San Francisco', 'CA', '94101'),
(17, 17, '590 Cypress Street', 'Indianapolis', 'IN', '46201'),
(18, 18, '710 Beech Avenue', 'Seattle', 'WA', '98101'),
(19, 19, '820 Hickory Road', 'Denver', 'CO', '80201'),
(20, 20, '930 Alder Court', 'Washington', 'DC', '20001');

-- Verify inserted data in parent (users) and child (addresses) tables
SELECT * FROM users;
SELECT * FROM addresses;

-- ==============================================================================
-- TABLE JOINS (INNER, RIGHT)
-- ==============================================================================

-- Example: Simple Inner Join retrieving user names with matching cities (Commented)
-- SELECT users.name, addresses.city FROM users INNER JOIN addresses ON users.id = addresses.user_id;

-- Detailed INNER JOIN: Retrieves matching rows from both users and addresses tables
SELECT users.id AS user_id, users.name, users.email, users.gender, users.date_of_birth, users.salary, addresses.street, addresses.city, addresses.state, addresses.pincode 
FROM users 
INNER JOIN addresses ON users.id = addresses.user_id;

-- Example: Left Join retrieving all users regardless of address presence (Commented)
-- SELECT users.id, users.name, addresses.city FROM users LEFT JOIN addresses ON users.id = addresses.user_id;

-- RIGHT JOIN: Returns all records from addresses table and matching user records
SELECT users.id, users.name, addresses.city FROM users RIGHT JOIN addresses ON user.id = addresses.user_id;

-- INNER JOIN: Standard join matching user IDs between tables
SELECT users.id, users.name, addresses.city FROM users INNER JOIN addresses ON user.id = addresses.user_id;

-- ==============================================================================
-- SET OPERATIONS (UNION & UNION ALL)
-- ==============================================================================

-- Ensure context database
USE startersql;

-- Create admin_users table structure with a CHECK constraint on gender
CREATE TABLE admin_users (
 id INT PRIMARY KEY,
 name VARCHAR(100),
 email VARCHAR(100),
 gender VARCHAR(10) CHECK (gender IN ('MALE', 'FEMALE', 'OTHER')),
 date_of_birth DATE,
 salary INT
);

-- Insert dummy data into admin_users
INSERT INTO admin_users (id, name, email, gender, date_of_birth, salary) VALUES
(1, 'Alice Johnson', 'alice.j@example.com', 'FEMALE', '1988-04-12', 85000.00),
(2, 'Robert Smith', 'robert.s@example.com', 'MALE', '1985-11-23', 92500.50),
(3, 'Charlie Davis', 'charlie.d@example.com', 'OTHER', '1992-07-08', 78000.00),
(4, 'Diana Prince', 'diana.p@example.com', 'FEMALE', '1990-01-30', 105000.00),
(5, 'Evan Wright', 'evan.w@example.com', 'MALE', '1983-09-15', 115000.75);

-- UNION: Combines distinct names from both tables (removes duplicates)
SELECT name FROM users UNION SELECT name FROM admin_users;

-- UNION: Combines unique name and email pairs across both tables
SELECT name, email FROM users UNION SELECT name, email FROM admin_users;

-- UNION ALL: Combines results keeping all rows including exact duplicates
SELECT name, email FROM users UNION ALL SELECT name, email FROM admin_users;

-- UNION with literal custom column ('ROLE'): Labels account origin as 'User' or 'Admin'
-- Note: Positional column ordering should match in both SELECT statements for accurate mapping
SELECT email, name, "User" AS ROLE FROM users UNION SELECT name, email, "Admin" as ROLE FROM admin_users;

-- UNION with ORDER BY: Merges distinct names and sorts final combined list alphabetically
SELECT name FROM users UNION SELECT name FROM admin_users ORDER BY name;

-- ==============================================================================
-- SELF JOIN (RELATING A TABLE TO ITSELF)
-- ==============================================================================

-- Add a self-referencing foreign key column to track user referrals
ALTER TABLE users ADD COLUMN referred_by_id INT;

-- Populate referral data linking users to referring user ID 1
UPDATE users SET referred_by_id = 1 WHERE id IN (2, 3, 13, 14, 19, 20);

-- Populate referral data linking users to referring user ID 2
UPDATE users SET referred_by_id = 2 WHERE id IN (1, 4, 10);

-- Display table contents after referral relationships are updated
SELECT * FROM users;

-- SELF JOIN: Join users table (a) with itself (b) to display user names alongside referrer names
SELECT
a.id,
a.name AS user_name,
b.name AS referred_by_name
FROM users a
INNER JOIN users b ON a.referred_by_id = b.id;

-- ==============================================================================
-- DATABASE VIEWS
-- ==============================================================================

-- Create a virtual table (View) that filters users earning over 60,000
CREATE VIEW rich_users AS SELECT * FROM users WHERE salary > 60000;

-- Query the created view like a standard table
SELECT * FROM rich_users;

-- Permanently drop/remove the view from database
DROP VIEW rich_users;

-- ==============================================================================
-- INDEX MANAGEMENT
-- ==============================================================================

-- Display existing indexes created on users table
SHOW indexes FROM users;

-- Create an index on the 'gender' column to optimize search query performance
CREATE INDEX idx_email ON users(gender);

-- Query using indexed fields (email and gender)
SELECT * FROM users WHERE email = "aarav.sharma@example.com" AND gender="MALE";

-- Drop the created index from users table
DROP INDEX idx_email ON users;

-- ==============================================================================
-- SUBQUERIES (SCALAR, MULTI-ROW & CORRELATED)
-- ==============================================================================

-- Calculate overall average salary across all users
SELECT AVG(salary) FROM users;

-- Scalar Subquery in WHERE clause: Find users whose salary is higher than overall average
SELECT * FROM users WHERE salary > (SELECT AVG(salary) FROM users);

-- Scalar Subquery displaying specific columns for users earning above average
SELECT id, name, salary FROM users WHERE salary > ( SELECT AVG(salary) FROM users);

-- Subquery with IN operator: Find users referred by anyone earning over 65,000
SELECT id, name, referred_by_id FROM users WHERE referred_by_id IN (SELECT id FROM users WHERE salary > 65000);

-- Nested Subquery with IN operator: Find users referred by anyone earning below average salary
SELECT id, name, referred_by_id FROM users WHERE referred_by_id IN (SELECT id FROM users WHERE salary < (SELECT AVG(salary) FROM users));

-- Scalar Subquery in SELECT clause: Appends overall average salary as an extra column to every row
SELECT name, salary, (SELECT AVG(salary) FROM users) AS average_salary FROM users;

-- ==============================================================================
-- GROUP BY & HAVING CLAUSE
-- ==============================================================================

-- Group rows by gender and calculate average salary for each gender category
SELECT gender as "Gender", AVG(salary) as "Average" FROM users GROUP BY gender;

-- Group by gender and return both average salary and total user count per group
SELECT gender as "Gender", AVG(salary) as "Average", COUNT(*) as "Count" FROM users GROUP BY gender;

-- Filter grouped results: HAVING filters groups AFTER aggregation (unlike WHERE)
SELECT gender as "Gender", AVG(salary) as "Average", COUNT(*) as "Count" 
FROM users 
GROUP BY gender 
HAVING AVG(salary) > 50000;

-- Apply multiple aggregate conditions using AND in the HAVING clause
SELECT gender as "Gender", AVG(salary) as "Average", COUNT(*) as "Count" 
FROM users 
GROUP BY gender 
HAVING AVG(salary) > 50000 AND COUNT(*) < 19;

-- Find users who have referred more than 1 other user (filtering out NULL referrers first)
SELECT referred_by_id, COUNT(*) AS total_referred 
FROM users 
WHERE referred_by_id IS NOT NULL 
GROUP BY referred_by_id 
HAVING COUNT(*) > 1;

-- Check all users table records
SELECT * FROM users;

-- ==============================================================================
-- WITH ROLLUP (SUBTOTALS & GRAND TOTALS)
-- ==============================================================================

-- WITH ROLLUP adds a summary super-aggregate row (grand total / overall average) at the end
SELECT gender as "Gender", AVG(salary) as "Average", COUNT(*) as "Count"
FROM users 
WHERE id < 5000 
GROUP BY gender WITH ROLLUP
HAVING AVG(salary) < 50000;

-- ==============================================================================
-- STORED PROCEDURES
-- ==============================================================================

-- View current records prior to stored procedure execution
SELECT * FROM users;

-- Change delimiter to $$ to safely write multi-statement procedure body
DELIMITER $$

-- Create a basic parameterless procedure to fetch all users
CREATE PROCEDURE select_users()
BEGIN
   SELECT * FROM USERS;
END $$

-- Reset custom delimiter back to default semicolon
DELIMITER ;

-- Execute / Invoke the stored procedure
CALL select_users();

-- Change delimiter for multi-statement procedure definition with IN parameters
DELIMITER $$

-- Create a parameterized procedure to insert a new user and return the updated table
CREATE PROCEDURE AddUser(
   IN p_name VARCHAR(100),
   IN p_email VARCHAR(100),
   IN p_gender ENUM("MALE", "FEMALE", "OTHER"),
   IN p_dob DATE,
   IN P_salary INT
)
BEGIN
   INSERT INTO users (name, email, gender, date_of_birth, salary)
   VALUES (p_name, p_email, p_gender, p_dob, P_salary);
   SELECT * FROM USERS;
END $$

DELIMITER ;

-- Call the procedure with input values
CALL AddUser("Eren Jaeger", "eren.jeager@gmail.com", "MALE", "2003-03-29", "1000000");

-- View all stored procedures existing within the 'startersql' database
SHOW PROCEDURE STATUS WHERE Db = "startersql";

-- Safely remove procedure if it exists
DROP PROCEDURE IF EXISTS AddUser;

-- ==============================================================================
-- TRIGGERS & AUDIT LOGGING
-- ==============================================================================

-- General Trigger Template:
-- CREATE TRIGGER trigger_name
-- AFTER INSERT ON table_name
-- FOR EACH ROW
-- BEGIN   
--     -- statements to execute
-- END;

-- Create an audit table to record user creation logs
CREATE TABLE user_log (
   id INT AUTO_INCREMENT PRIMARY KEY,
   user_id INT,
   name VARCHAR(100),
   created_on TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Define trigger that automatically logs entry into user_log whenever a new user is inserted
DELIMITER $$
CREATE TRIGGER after_user_insert
AFTER INSERT ON users
FOR EACH ROW
BEGIN
   INSERT INTO user_log (user_id, name)
   VALUES (NEW.id, NEW.name);
END $$
DELIMITER ;

-- Test the trigger by inserting a new record into users
INSERT INTO users (name, email, gender, date_of_birth, salary) VALUES
("Akhil Shetty", "akhil@gmail.com", "MALE", "2003-03-29", 10000000);

-- Verify the new record in users table
SELECT * FROM users;

-- Verify the automated audit log entry
SELECT * FROM user_log;

-- Delete trigger if no longer needed
DROP TRIGGER IF EXISTS after_user_insert;

-- ==============================================================================
-- WILDCARD OPERATORS (LIKE)
-- ==============================================================================

-- Find names starting with 'a' or 'A' (% matches zero or more characters)
SELECT * FROM users WHERE name LIKE "a%";

-- Find names where the second letter is 'a' (_ matches exactly one character)
SELECT * FROM users WHERE name LIKE "_a_%";

-- Find names where the second letter is 'a' and the fourth letter is 'h'
SELECT * FROM users WHERE name LIKE "_a_h%";

-- ==============================================================================
-- PAGINATION (LIMIT AND OFFSET)
-- ==============================================================================

-- Standard Syntax: Fetch 5 records, skipping the first 3 rows (Rows 4 to 8)
SELECT * FROM users ORDER BY id LIMIT 5 OFFSET 3;

-- Shorthand Syntax: LIMIT offset, count (Skips 5 rows, fetches next 3 rows)
SELECT * FROM users ORDER BY id LIMIT 5, 3;

-- ==============================================================================
-- DISTINCT KEYWORD
-- ==============================================================================

-- Return only unique/non-duplicate values from the gender column
SELECT DISTINCT gender FROM users;

-- ==============================================================================
-- TRUNCATE TABLE
-- ==============================================================================

-- TRUNCATE: Instantly removes all rows and resets AUTO_INCREMENT counters.
-- Keeps the table structure intact. (Faster than DELETE, cannot be rolled back in DDL mode).
TRUNCATE TABLE users;

-- ==============================================================================
-- ALTER TABLE: CHANGE vs MODIFY COLUMN
-- ==============================================================================

-- CHANGE: Used to rename a column AND/OR change its data type simultaneously
ALTER TABLE users CHANGE COLUMN city location VARCHAR(150);

-- MODIFY: Used to change data type, length, or constraints WITHOUT renaming the column
ALTER TABLE users MODIFY COLUMN salary BIGINT;