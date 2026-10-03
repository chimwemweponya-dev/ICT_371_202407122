DROP TABLE IF EXISTS allocations;
DROP TABLE IF EXISTS hostel_rooms;
DROP PROCEDURE IF EXISTS allocate_room(VARCHAR, INT);
DROP PROCEDURE IF EXISTS check_out(INT);

CREATE TABLE hostel_rooms (
    room_id SERIAL PRIMARY KEY,
    room_number VARCHAR(10) NOT NULL UNIQUE,
    available_spaces INT NOT NULL CHECK (available_spaces >= 0)
);

CREATE TABLE allocations (
    allocation_id SERIAL PRIMARY KEY,
    student_number VARCHAR(20) NOT NULL,
    room_id INT NOT NULL REFERENCES hostel_rooms(room_id),
    status VARCHAR(15) NOT NULL DEFAULT 'ALLOCATED',
    allocated_on TIMESTAMP NOT NULL DEFAULT NOW()
);

INSERT INTO hostel_rooms (room_number, available_spaces)
VALUES
    ('A101', 4),
    ('B202', 2),
    ('C303', 0);

SELECT * FROM hostel_rooms ORDER BY room_id;

DO $$
DECLARE
    rec RECORD;
BEGIN
    FOR rec IN
        SELECT room_number, available_spaces
        FROM hostel_rooms
        ORDER BY room_id
    LOOP
        IF rec.available_spaces = 0 THEN
            RAISE NOTICE 'Room % is FULL', rec.room_number;
        ELSIF rec.available_spaces = 1 THEN
            RAISE NOTICE 'Room % has ONE space left', rec.room_number;
        ELSE
            RAISE NOTICE 'Room % has SEVERAL spaces (%)',
                rec.room_number,
                rec.available_spaces;
        END IF;
    END LOOP;
END;
$$;

DO $$
DECLARE
    d INT := 1;
BEGIN
    WHILE d <= 3 LOOP
        RAISE NOTICE 'Hostel inspection day %', d;
        d := d + 1;
    END LOOP;

    FOR chk IN 1..3 LOOP
        RAISE NOTICE 'Room check number %', chk;
    END LOOP;
END;
$$;

CREATE OR REPLACE PROCEDURE allocate_room(
    p_student_number VARCHAR,
    p_room_id INT
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_spaces INT;
BEGIN
    IF p_student_number IS NULL
       OR TRIM(p_student_number) = '' THEN
        RAISE EXCEPTION
            'Invalid input: student number cannot be blank';
    END IF;

    SELECT available_spaces
    INTO v_spaces
    FROM hostel_rooms
    WHERE room_id = p_room_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION
            'Room % does not exist',
            p_room_id;
    END IF;

    IF v_spaces < 1 THEN
        RAISE NOTICE
            'Allocation REJECTED for student %: room % is full',
            p_student_number,
            p_room_id;
        RETURN;
    END IF;

    UPDATE hostel_rooms
    SET available_spaces = available_spaces - 1
    WHERE room_id = p_room_id;

    INSERT INTO allocations(student_number, room_id)
    VALUES(TRIM(p_student_number), p_room_id);

    RAISE NOTICE
        'Student % allocated to room %',
        p_student_number,
        p_room_id;
END;
$$;

CALL allocate_room('ST001', 1);
CALL allocate_room('ST002', 2);
CALL allocate_room('ST003', 3);

SELECT * FROM hostel_rooms;
SELECT * FROM allocations;

CREATE OR REPLACE PROCEDURE check_out(
    p_allocation_id INT
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_room_id INT;
    v_status VARCHAR(15);
BEGIN
    SELECT room_id, status
    INTO v_room_id, v_status
    FROM allocations
    WHERE allocation_id = p_allocation_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION
            'Allocation % does not exist',
            p_allocation_id;
    END IF;

    IF v_status = 'COMPLETED' THEN
        RAISE NOTICE
            'Allocation % already checked out. No space freed.',
            p_allocation_id;
        RETURN;
    END IF;

    UPDATE allocations
    SET status = 'COMPLETED'
    WHERE allocation_id = p_allocation_id;

    UPDATE hostel_rooms
    SET available_spaces = available_spaces + 1
    WHERE room_id = v_room_id;

    RAISE NOTICE
        'Allocation % checked out. One space freed in room %.',
        p_allocation_id,
        v_room_id;
END;
$$;

CALL check_out(1);
CALL check_out(1);

SELECT * FROM hostel_rooms ORDER BY room_id;
SELECT * FROM allocations ORDER BY allocation_id;

DO $$
DECLARE
    cur_rooms CURSOR FOR
        SELECT room_number, available_spaces
        FROM hostel_rooms
        WHERE available_spaces <= 1
        ORDER BY room_number;

    rec RECORD;
BEGIN
    OPEN cur_rooms;

    LOOP
        FETCH cur_rooms INTO rec;
        EXIT WHEN NOT FOUND;

        IF rec.available_spaces = 0 THEN
            RAISE NOTICE 'Room % is FULL', rec.room_number;
        ELSE
            RAISE NOTICE 'Room % is NEARLY FULL (% space left)',
                rec.room_number,
                rec.available_spaces;
        END IF;
    END LOOP;

    CLOSE cur_rooms;
END;
$$;

DO $$
BEGIN
    CALL allocate_room('   ', 1);
EXCEPTION
    WHEN raise_exception THEN
        RAISE NOTICE 'Error handled: %', SQLERRM;
END;
$$;

SELECT room_id, room_number, available_spaces
FROM hostel_rooms
ORDER BY room_id;

SELECT allocation_id, student_number, room_id, status
FROM allocations
ORDER BY allocation_id;