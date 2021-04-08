
/*****************
 * User functions
 *****************/

/** 
 * add_customer(): used to add a new customer
 */
CREATE OR REPLACE PROCEDURE add_customer(name text, address text, phone int, email text, 
    card_number text, expiry_date date, CVV text)
AS $$
DECLARE
    cid int;
BEGIN
    if (expiry_date < current_date) then
        raise exception 'Credit card expired: %', expiry_date
            using hint = 'Please check your expiry date';
    end if;

    -- generate id
    select coalesce(max(cust_id), 0) + 1 into cid
    from customers;

    -- insert into relevant tables
    insert into Customers 
    values (cid, name, address, phone, email);
    
    insert into Credit_cards 
    values (card_number, CVV, expiry_date, cid, now());
END
$$ language plpgsql;


-----

/**
 * update_credit_card(): Used when a customer request to change credit card details
 *      1. Creates new credit card when a new card number is used
 *      2. Update card details if card number is the same
 */
CREATE OR REPLACE PROCEDURE update_credit_card(cid int, c_number text, c_expiry date, c_cvv text)
AS $$
DECLARE
    rec credit_cards;
BEGIN
    if (c_expiry < current_date) then
        raise exception 'New credit card expired: %', c_expiry
            using hint = 'Please check your expiry date';

    elsif (not exists(select 1 from Customers where cust_id = cid)) then
        raise exception 'Non-existent customer id: %', cid
            using hint = 'Please check customer ID or use add_customer to add';

    end if;

    if (exists(select 1 from credit_cards where cust_id = cid and card_number = c_number)) then

        update Credit_cards
        set from_date = now(), 
            expiry_date = c_expiry, 
            CVV = c_cvv
        where cust_id = cid and card_number = c_number;
    else 
        insert into Credit_cards
        values (c_number, c_cvv, c_expiry, cid, now());
    end if;
END
$$ language plpgsql;


/*******************
 * HELPER FUNCTIONS
 *******************/

/**
 * get_active_card():
 * Helper function used internally to get the current active card of a customer.
 * Raises exception if the customer is invalid or the active card is expired.
 */
CREATE OR REPLACE FUNCTION get_active_card(cid int)
returns Credit_cards as $$
DECLARE
    active_card Credit_cards;
BEGIN
    if not exists(select 1 from Customers where cust_id = cid) then
        raise exception 'Non-existent customer id %', cid;
        return NULL;
    end if;

    select * into active_card
    from Credit_cards 
    where cust_id = cid 
    order by from_date 
    desc limit 1;

    if not found then
        raise exception 'Internal error: No credit card found for customer id %', cid 
            using hint = 'Please add a new credit card';

        return NULL;
    elsif (active_card.expiry_date < current_date) then
        raise exception 'Credit card for customer % expired', cid;

        return NULL;
    end if;

    return active_card;
END
$$ language plpgsql;

