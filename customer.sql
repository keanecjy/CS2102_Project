/**
 * Temporary file used to avoid merge conflict.
 * Recommend to combine the functions after everything is completed
 */

CREATE OR REPLACE FUNCTION add_customer(name text, address text, phone int, email text, 
    card_number text, expiry_date date, CVV int)
RETURNS text AS $$
DECLARE
    cid int;
BEGIN
    select coalesce(max(cust_id), 0) + 1 into cid
    from customers;

    insert into Customers 
    values (cid, name, address, phone, email)
    returning cust_id into cid;

    insert into Credit_cards 
    values (card_number, CVV, expiry_date, cid, now());

    return 'Successfully added customer id ' || cid;
END
$$ language plpgsql;


-----


CREATE OR REPLACE FUNCTION update_credit_card(cid int, c_number text, expiry date, cvv int)
RETURNS text as $$
BEGIN
    if (expiry < current_date) then
        raise exception 'Credit card expired --> %', expiry
            using hint = 'Please check your expiry date';
        return 'Unsuccessful';

    elsif (not exists(select 1 from Customers where cust_id = cid)) then
        raise exception 'Nonexistent customer id --> %', cid
            using hint = 'Please check customer ID or use add_customer to add';
        return 'Unsuccessful';
    end if;

    if (exists(select 1 from credit_cards where cust_id = cid and card_number = c_number)) then
        -- update 'inactive' card to active card

        update Credit_cards
        set from_date = now();

    else 
        insert into Credit_cards 
        values (c_number, cvv, expiry, cid, now());
    end if;

    return 'Successful';
END
$$ language plpgsql;



-- Helpful functions for getting active card easily
CREATE OR REPALCE FUNCTION get_active_card(cid int)
returns Credit_cards as $$
DECLARE active_card Credit_cards;
BEGIN    
    select * into active_card
    from Credit_cards 
    where cust_id = cid 
    order by from_date 
    desc limit 1;

    if not found then
        raise notice 'No credit card found';
        return NULL;
    end if;

    return active_card;
END
$$ language plpgsql;

