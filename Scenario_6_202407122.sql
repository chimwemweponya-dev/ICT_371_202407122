DROP TABLE IF EXISTS bookings;
DROP TABLE IF EXISTS events;
DROP PROCEDURE IF EXISTS book_seats(INT, VARCHAR, INT);
DROP PROCEDURE IF EXISTS cancel_booking(INT);

CREATE TABLE events (
    event_id        SERIAL PRIMARY KEY,
    event_name      VARCHAR(100) NOT NULL,
    available_seats INT NOT NULL CHECK (available_seats >= 0)
);
CREATE TABLE bookings (
    booking_id     SERIAL PRIMARY KEY,
    event_id       INT NOT NULL REFERENCES events(event_id),
    student_number VARCHAR(20) NOT NULL,
    seats          INT NOT NULL CHECK (seats > 0),
    status         VARCHAR(15) NOT NULL DEFAULT 'BOOKED',
    booked_on      TIMESTAMP NOT NULL DEFAULT now()
);

INSERT INTO events (event_name, available_seats) VALUES
    ('Career Fair', 100),
    ('Graduation Gala', 8),
    ('Hackathon Finals', 0);   -- already full

SELECT * FROM events ORDER BY event_id;

DO $$
DECLARE
    rec RECORD;
BEGIN
    FOR rec IN SELECT event_name, available_seats FROM events ORDER BY event_id LOOP
        IF rec.available_seats = 0 THEN
            RAISE NOTICE '% : FULL', rec.event_name;
        ELSIF rec.available_seats <= 10 THEN
            RAISE NOTICE '% : NEARLY FULL (% seats left)', rec.event_name, rec.available_seats;
        ELSE
            RAISE NOTICE '% : PLENTY of seats (%)', rec.event_name, rec.available_seats;
        END IF;
    END LOOP;
END $$;

DO $$
DECLARE
    d INT := 1;
BEGIN
    WHILE d <= 3 LOOP
        RAISE NOTICE 'Booking reminder day %', d;
        d := d + 1;
    END LOOP;

    FOR chk IN 1..3 LOOP
        RAISE NOTICE 'Entrance check number %', chk;
    END LOOP;
END $$;

CREATE OR REPLACE PROCEDURE book_seats(
    p_event_id INT,
    p_student_number VARCHAR,
    p_seats INT
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_available INT;
BEGIN
    IF p_seats IS NULL OR p_seats <= 0 THEN
        RAISE EXCEPTION 'Invalid number of seats: % (must be greater than zero)', p_seats;
    END IF;

    SELECT available_seats INTO v_available
    FROM events WHERE event_id = p_event_id FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Event % does not exist', p_event_id;
    END IF;

    IF v_available < p_seats THEN
        RAISE NOTICE 'Booking REJECTED for student %: requested %, only % seats left',
                     p_student_number, p_seats, v_available;
        RETURN;
    END IF;

    UPDATE events SET available_seats = available_seats - p_seats
    WHERE event_id = p_event_id;

    INSERT INTO bookings (event_id, student_number, seats)
    VALUES (p_event_id, p_student_number, p_seats);

    RAISE NOTICE 'Booking recorded: student %, event %, seats %', p_student_number, p_event_id, p_seats;
END;
$$;

CALL book_seats(1, '2024001', 4);
CALL book_seats(2, '2024002', 3);   
CALL book_seats(2, '2024003', 10); 

SELECT * FROM events ORDER BY event_id;
SELECT * FROM bookings ORDER BY booking_id;

CREATE OR REPLACE PROCEDURE cancel_booking(p_booking_id INT)
LANGUAGE plpgsql
AS $$
DECLARE
    v_event_id INT;
    v_seats    INT;
    v_status   VARCHAR(15);
BEGIN
    SELECT event_id, seats, status
    INTO v_event_id, v_seats, v_status
    FROM bookings WHERE booking_id = p_booking_id FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Booking % does not exist', p_booking_id;
    END IF;

    IF v_status = 'CANCELLED' THEN
        RAISE NOTICE 'Booking % was already cancelled. No seats released.', p_booking_id;
        RETURN;
    END IF;

    UPDATE bookings SET status = 'CANCELLED' WHERE booking_id = p_booking_id;
    UPDATE events SET available_seats = available_seats + v_seats WHERE event_id = v_event_id;

    RAISE NOTICE 'Booking % cancelled. % seats released.', p_booking_id, v_seats;
END;
$$;

CALL cancel_booking(1);   -- first call: releases seats
CALL cancel_booking(1);   -- second call: must NOT release seats again

SELECT * FROM events ORDER BY event_id;
SELECT * FROM bookings ORDER BY booking_id;

DO $$
DECLARE
    cur_events CURSOR FOR
        SELECT event_name, available_seats
        FROM events WHERE available_seats <= 10 ORDER BY available_seats;
    rec RECORD;
BEGIN
    OPEN cur_events;
    LOOP
        FETCH cur_events INTO rec;
        EXIT WHEN NOT FOUND;
        IF rec.available_seats = 0 THEN
            RAISE NOTICE '% is FULL', rec.event_name;
        ELSE
            RAISE NOTICE '% is NEARLY FULL (% seats left)', rec.event_name, rec.available_seats;
        END IF;
    END LOOP;
    CLOSE cur_events;
END $$;

DO $$
BEGIN
    CALL book_seats(1, '2024004', 0);
EXCEPTION
    WHEN raise_exception THEN
        RAISE NOTICE 'Error handled: %', SQLERRM;
END $$;

SELECT event_id, event_name, available_seats FROM events ORDER BY event_id;
SELECT booking_id, event_id, student_number, seats, status FROM bookings ORDER BY booking_id;