-- Can Change Database name
SET @MPDBName = 'MacPatchDB3';
-- Can Change Main MacPatch User name
SET @MPDBUser = 'mpdbadm';
-- Must Change Main MacPatch User password
SET @MPDBUserPass = '0PleaseChangeMe!';

SET @query = CONCAT('DROP USER IF EXISTS ', @MPDBUser ,'@localhost');
PREPARE stmt FROM @query; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @query = CONCAT('DROP USER IF EXISTS ', @MPDBUser ,'@"%"');
PREPARE stmt FROM @query; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @query = CONCAT('CREATE DATABASE IF NOT EXISTS ', @MPDBName);
PREPARE stmt FROM @query; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @query = CONCAT('CREATE USER ', @MPDBUser ,'@"%" IDENTIFIED BY "',@MPDBUserPass,'"');
PREPARE stmt FROM @query; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @query = CONCAT('GRANT ALL PRIVILEGES ON ', @MPDBName, '.* TO ', @MPDBUser,'@"%"');
PREPARE stmt FROM @query; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @query = CONCAT('CREATE USER ', @MPDBUser ,'@"localhost" IDENTIFIED BY "',@MPDBUserPass,'"');
PREPARE stmt FROM @query; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @query = CONCAT('GRANT ALL PRIVILEGES ON ', @MPDBName, '.* TO ', @MPDBUser,'@localhost');
PREPARE stmt FROM @query; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET GLOBAL log_bin_trust_function_creators = 1;
SET PERSIST sql_mode=(SELECT REPLACE(@@sql_mode,'ONLY_FULL_GROUP_BY',''));
DELETE FROM mysql.user WHERE User='';
FLUSH PRIVILEGES;