CREATE OR REPLACE PROCEDURE register_session(cus_id INT, cid INT, date_of_launch DATE, session_number INT, card_number TEXT,
                                             buy_date DATE, pid INT, pay_method TEXT)
AS $$
DECLARE
    deadline Date;
    session_date Date;
    capacity INT;
    num_reg INT;
    num_redeem INT;
BEGIN
    /*
     * 1) Check if current_date have already past the session_date itself
     * 2) Check if current_date have already past the registration_deadline
     * 3) Check if number of registration + redeems <= seating_capacity
     * 4) If redeems, check if the number of redeems of that package_id < num_free_registrations. Means check if package is active?
     * 5) Check if there is any session of this course that exist before (In unique_session_per_course_redeem_checks AND unique_session_per_course_register_checks)
     */
    /*
     * Dont need to check validity of buy_date, pid, card_number, session_number, cid, date_of_launch etc as it should be check via the foreign key?
     */
    SELECT registration_deadline, seating_capacity INTO deadline, capacity
    FROM Offerings
    WHERE launch_date = date_of_launch
      AND course_id = cid;

    IF (current_date > deadline) THEN
        RAISE EXCEPTION 'The registration deadline for this course have already have passed!';
    END IF;

    SELECT S.session_date INTO session_date
    FROM Sessions S
    WHERE launch_date = date_of_launch
      AND course_id = cid
      AND S.sid = session_number;

    IF (current_date > session_date) THEN
        RAISE EXCEPTION 'This session have already passed, you cant register for it';
    END IF;

    SELECT COUNT(*) INTO num_reg
    FROM Registers R
    WHERE R.sid = session_number
      AND R.launch_date = date_of_launch
      AND R.course_id = cid;

    SELECT COUNT(*) INTO num_redeem
    FROM Redeems R
    WHERE R.sid = session_number
      AND R.launch_date = date_of_launch
      AND R.course_id = cid;

    IF (num_reg + num_redeem + 1 > capacity) THEN
        RAISE EXCEPTION 'This session course is already full!';
    END IF;

    IF (pay_method = 'redeem' AND buy_date IS NOT NULL AND pid IS NOT NULL) THEN
        IF ((SELECT num_remaining_redemptions FROM Buys B WHERE B.buy_date = buy_date AND B.cust_id = cus_id AND B.package_id = pid) = 0) THEN
            RAISE EXCEPTION 'This course package has used up all its available free redeems';
        END IF;

        INSERT INTO Redeems VALUES (current_date, buy_date, cus_id, pid, session_number, date_of_launch, cid);

        -- decrement the num of remaining redemptions for that particular package
        UPDATE Buys B
        SET num_remaining_redemptions = num_remaining_redemptions - 1
        WHERE B.buy_date = buy_date
          AND B.cust_id = cus_id
          AND B.package_id = pid;

    ELSIF (pay_method = 'card' AND card_number IS NOT NULL) THEN
        INSERT INTO Registers VALUES (current_date, cus_id, card_number, session_number, date_of_launch, cid);
    ELSE
        RAISE EXCEPTION 'INVALID PAYMENT METHOD';
    END IF;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE PROCEDURE cancel_registration(cus_id INT, cid INT, date_of_launch DATE)
AS $$
DECLARE
    sid_register INT;
    sid_redeem INT;
    session_date DATE;
    buy_date DATE;
    pid INT;
BEGIN
    -- we know that for a course, that customer only have 1 session
    -- if cancelled at least 7 days before the day of registered sessions, will have to credit an extra course session to customer 
    SELECT R.sid, R.buy_date, R.package_id INTO sid_redeem, buy_date, pid
    FROM Redeems R
    WHERE R.cust_id = cus_id
      AND R.course_id = cid
      AND R.launch_date = date_of_launch;

    SELECT R.sid INTO sid_register
    FROM Registers R
    WHERE R.cust_id = cus_id
      AND R.course_id = cid
      AND R.launch_date = date_of_launch;

    IF (sid_redeem IS NULL AND sid_register IS NULL) THEN
        RAISE EXCEPTION 'This customer does not have any session for this course';
    END IF;


    IF (sid_redeem IS NOT NULL) THEN
        -- DELETE FROM redeems
        SELECT S.session_date INTO session_date
        FROM Sessions S
        WHERE S.sid = sid
          AND S.course_id = cid
          AND S.launch_date = date_of_launch;

        IF ((SELECT (session_date - current_date) AS days) >= 7) THEN
            UPDATE Buys B
            SET num_remaining_redemptions = num_remaining_redemptions + 1
            WHERE B.buy_date = buy_date
              AND B.cust_id = cus_id
              AND B.package_id = pid;
        END IF;

        DELETE FROM Redeems R
        WHERE R.cust_id = cus_id
          AND R.course_id = cid
          AND R.launch_date = date_of_launch;
    ELSE
        -- DELETE FROM registers
        DELETE FROM Registers R
        WHERE R.cust_id = cus_id
          AND R.course_id = cid
          AND R.launch_date = date_of_launch;
    END IF;
END;
$$ LANGUAGE plpgsql;

-- course_name = title
-- sorted by session_date, start_hour
-- course_name, duration (Courses)
-- course_fee (Offerings)
-- session_date, start_hour (Sessions)
-- Instructor_name (Specializes)
CREATE OR REPLACE FUNCTION get_my_registrations(IN cus_id INT)
    RETURNS TABLE (course_name TEXT, course_fee FLOAT, session_date DATE, start_hour TIME, duration INT, instructor_name TEXT) AS $$
DECLARE
BEGIN
    with
        Q0 AS (SELECT launch_date, course_id, fees FROM Offerings),
        Q1 AS (SELECT * FROM (Specializes NATURAL JOIN Courses NATURAL JOIN Q0 NATURAL JOIN Sessions)),
        Q2 AS (SELECT * FROM (Q1 NATURAL JOIN Redeems) WHERE cust_id = cus_id AND session_date > current_date),
        Q3 AS (SELECT * FROM (Q1 NATURAL JOIN Registers) WHERE cust_id = cus_id AND session_date > current_date)
    SELECT *
    FROM (SELECT Q2.title, Q2.fees, Q2.session_date, Q2.start_time, Q2.duration, Q2.name FROM Q2
          UNION
          SELECT Q3.title, Q3.fees, Q3.session_date, Q3.start_time, Q3.duration, Q3.name FROM Q3) AS ANS
    ORDER BY (session_date, start_hour);
END;
$$ LANGUAGE plpgsql;




