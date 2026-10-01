DROP TABLE IF EXISTS contract_recipe CASCADE;
DROP TABLE IF EXISTS order_item_topping CASCADE;
DROP TABLE IF EXISTS write_off CASCADE;
DROP TABLE IF EXISTS violation CASCADE;
DROP TABLE IF EXISTS quality_check CASCADE;
DROP TABLE IF EXISTS local_price CASCADE;
DROP TABLE IF EXISTS order_item CASCADE;
DROP TABLE IF EXISTS customer_order CASCADE;
DROP TABLE IF EXISTS discrepancy_act CASCADE;
DROP TABLE IF EXISTS product_batch CASCADE;
DROP TABLE IF EXISTS supply CASCADE;
DROP TABLE IF EXISTS incompatibility_rule CASCADE;
DROP TABLE IF EXISTS recipe CASCADE;
DROP TABLE IF EXISTS semi_finished_product CASCADE;
DROP TABLE IF EXISTS topping CASCADE;
DROP TABLE IF EXISTS base_product CASCADE;
DROP TABLE IF EXISTS sales_point CASCADE;
DROP TABLE IF EXISTS franchise_contract CASCADE;
DROP TABLE IF EXISTS franchisee CASCADE;


DROP TYPE IF EXISTS resolution_status_enum CASCADE;
DROP TYPE IF EXISTS criticality_enum CASCADE;
DROP TYPE IF EXISTS check_result_enum CASCADE;
DROP TYPE IF EXISTS check_type_enum CASCADE;
DROP TYPE IF EXISTS write_off_reason_enum CASCADE;
DROP TYPE IF EXISTS order_status_enum CASCADE;
DROP TYPE IF EXISTS order_item_status_enum CASCADE;
DROP TYPE IF EXISTS act_confirmation_enum CASCADE;
DROP TYPE IF EXISTS batch_status_enum CASCADE;
DROP TYPE IF EXISTS supply_status_enum CASCADE;
DROP TYPE IF EXISTS recipe_status_enum CASCADE;
DROP TYPE IF EXISTS unit_enum CASCADE;
DROP TYPE IF EXISTS restriction_type_enum CASCADE;
DROP TYPE IF EXISTS incompatibility_status_enum CASCADE;
DROP TYPE IF EXISTS product_status_enum CASCADE;
DROP TYPE IF EXISTS topping_status_enum CASCADE;
DROP TYPE IF EXISTS contract_status_enum CASCADE;
DROP TYPE IF EXISTS franchisee_status_enum CASCADE;
DROP TYPE IF EXISTS point_status_enum CASCADE;
DROP TYPE IF EXISTS point_format_enum CASCADE;







CREATE TYPE point_format_enum AS ENUM ('кафе', 'киоск', 'фуд-корт');
CREATE TYPE point_status_enum AS ENUM ('действующая', 'закрыта', 'на ремонте');
CREATE TYPE franchisee_status_enum AS ENUM ('действующий', 'расторгнут');
CREATE TYPE contract_status_enum AS ENUM ('действует', 'истёк', 'расторгнут');
CREATE TYPE product_status_enum AS ENUM ('в продаже', 'снято с продажи');
CREATE TYPE topping_status_enum AS ENUM ('в продаже', 'снята с продажи');
CREATE TYPE restriction_type_enum AS ENUM ('запрет сочетания', 'ограничение количества');
CREATE TYPE incompatibility_status_enum AS ENUM ('действует', 'не действует');
CREATE TYPE unit_enum AS ENUM ('кг', 'л', 'шт');
CREATE TYPE recipe_status_enum AS ENUM ('черновик', 'действует', 'архив');
CREATE TYPE supply_status_enum AS ENUM ('отправлена', 'принята', 'расхождение');
CREATE TYPE batch_status_enum AS ENUM ('на хранении', 'исчерпана', 'списана');
CREATE TYPE act_confirmation_enum AS ENUM ('не подтверждён', 'подтверждён', 'отклонён');
CREATE TYPE order_item_status_enum AS ENUM ('в заказе', 'приготовлена', 'отменена');
CREATE TYPE order_status_enum AS ENUM ('оформлен', 'готовится', 'выдан', 'отменён');
CREATE TYPE write_off_reason_enum AS ENUM ('производственное списание', 'отмена приготовленной позиции', 'порча', 'истёк срок');
CREATE TYPE check_type_enum AS ENUM ('плановая', 'внеплановая');
CREATE TYPE check_result_enum AS ENUM ('пройдена', 'выявлены нарушения');
CREATE TYPE criticality_enum AS ENUM ('низкая', 'средняя', 'высокая');
CREATE TYPE resolution_status_enum AS ENUM ('открыто', 'в работе', 'устранено');







-- Франчайзи/E2
CREATE TABLE franchisee (
    franchisee_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    inn CHAR(12) NOT NULL UNIQUE,
    full_name VARCHAR(100) NOT NULL,
    phone CHAR(11),
    status franchisee_status_enum NOT NULL
);

-- Договор франшизы/E3
CREATE TABLE franchise_contract (
    contract_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    franchisee_id UUID NOT NULL REFERENCES franchisee(franchisee_id) ON DELETE RESTRICT ON UPDATE CASCADE,
    contract_number VARCHAR(50) NOT NULL UNIQUE,
    conclusion_date DATE NOT NULL,
    start_date DATE NOT NULL,
    end_date DATE NOT NULL,
    assortment TEXT,
    local_changes TEXT,
    control_procedure TEXT,
    status contract_status_enum NOT NULL
);

-- Точка продаж/E1
CREATE TABLE sales_point (
    sales_point_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    franchisee_id UUID NOT NULL REFERENCES franchisee(franchisee_id) ON DELETE RESTRICT ON UPDATE CASCADE,
    contract_id UUID NOT NULL REFERENCES franchise_contract(contract_id) ON DELETE RESTRICT ON UPDATE CASCADE,
    name VARCHAR(100) NOT NULL UNIQUE,
    address VARCHAR(100) NOT NULL,
    format point_format_enum NOT NULL,
    status point_status_enum NOT NULL
);

-- Базовое изделие/E4
CREATE TABLE base_product (
    product_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name VARCHAR(100) NOT NULL UNIQUE,
    base_price DECIMAL(10,2) NOT NULL CHECK (base_price >= 0),
    status product_status_enum NOT NULL
);

-- Начинка/E5
CREATE TABLE topping (
    topping_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name VARCHAR(50) NOT NULL UNIQUE,
    composition TEXT,
    surcharge DECIMAL(10,2) NOT NULL CHECK (surcharge >= 0),
    status topping_status_enum NOT NULL
);

-- Несовместимость/E6
CREATE TABLE incompatibility_rule (
    product_id UUID NOT NULL REFERENCES base_product(product_id) ON DELETE CASCADE ON UPDATE CASCADE,
    topping_id UUID NOT NULL REFERENCES topping(topping_id) ON DELETE CASCADE ON UPDATE CASCADE,
    restriction_type restriction_type_enum NOT NULL,
    limit_value INT CHECK (limit_value > 0),
    start_date DATE NOT NULL,
    end_date DATE,
    status incompatibility_status_enum NOT NULL,
    PRIMARY KEY (product_id, topping_id)
);

-- Полуфабрикат/E8
CREATE TABLE semi_finished_product (
    semi_finished_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name VARCHAR(50) NOT NULL UNIQUE,
    unit unit_enum NOT NULL,
    shelf_life_days INT NOT NULL CHECK (shelf_life_days > 0),
    storage_conditions VARCHAR(100)
);

-- Рецептура/E7
CREATE TABLE recipe (
    recipe_id UUID NOT NULL DEFAULT gen_random_uuid(),
    version INT NOT NULL,
    semi_finished_id UUID NOT NULL REFERENCES semi_finished_product(semi_finished_id) ON DELETE RESTRICT ON UPDATE CASCADE,
    product_id UUID NOT NULL REFERENCES base_product(product_id) ON DELETE RESTRICT ON UPDATE CASCADE,
    composition_norms TEXT NOT NULL,
    start_date DATE NOT NULL,
    end_date DATE,
    responsible VARCHAR(50),
    status recipe_status_enum NOT NULL,
    PRIMARY KEY (recipe_id, version)
);

-- Поставка/E10
CREATE TABLE supply (
    supply_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    sales_point_id UUID NOT NULL REFERENCES sales_point(sales_point_id) ON DELETE RESTRICT ON UPDATE CASCADE,
    supply_number INT NOT NULL UNIQUE,
    arrival_date DATE NOT NULL,
    supplier_name VARCHAR(50) NOT NULL,
    sent_qty INT NOT NULL CHECK (sent_qty >= 0),
    received_qty INT CHECK (received_qty >= 0),
    responsible VARCHAR(50),
    status supply_status_enum NOT NULL
);

-- Партия полуфабриката/E9
CREATE TABLE product_batch (
    semi_finished_id UUID NOT NULL,
    batch_number INT NOT NULL,
    sales_point_id UUID NOT NULL REFERENCES sales_point(sales_point_id) ON DELETE RESTRICT ON UPDATE CASCADE,
    supply_id UUID NOT NULL REFERENCES supply(supply_id) ON DELETE RESTRICT ON UPDATE CASCADE,
    arrival_date DATE NOT NULL,
    initial_qty INT NOT NULL CHECK (initial_qty > 0),
    expiry_date DATE NOT NULL,
    current_stock INT NOT NULL CHECK (current_stock >= 0),
    status batch_status_enum NOT NULL,
    PRIMARY KEY (semi_finished_id, batch_number),
    FOREIGN KEY (semi_finished_id) REFERENCES semi_finished_product(semi_finished_id) ON DELETE RESTRICT ON UPDATE CASCADE
);

-- Акт расхождения/E11
CREATE TABLE discrepancy_act (
    act_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    supply_id UUID NOT NULL REFERENCES supply(supply_id) ON DELETE RESTRICT ON UPDATE CASCADE,
    act_number INT NOT NULL UNIQUE,
    act_date DATE NOT NULL DEFAULT CURRENT_DATE,
    discrepancies_list TEXT NOT NULL,
    confirmation_status act_confirmation_enum NOT NULL DEFAULT 'не подтверждён',
    responsible VARCHAR(50),
    comment TEXT
);

-- Заказ/E12
CREATE TABLE customer_order (
    order_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    sales_point_id UUID NOT NULL REFERENCES sales_point(sales_point_id) ON DELETE RESTRICT ON UPDATE CASCADE,
    order_number INT NOT NULL UNIQUE,
    order_time TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    customer_name VARCHAR(50),
    total_cost DECIMAL(10,2) NOT NULL CHECK (total_cost >= 0),
    status order_status_enum NOT NULL,
    responsible VARCHAR(50)
);

-- Позиция заказа/E13
CREATE TABLE order_item (
    order_id UUID NOT NULL,
    item_number INT NOT NULL,
    product_id UUID NOT NULL REFERENCES base_product(product_id) ON DELETE RESTRICT ON UPDATE CASCADE,
    recipe_id UUID NOT NULL,
    recipe_version INT NOT NULL,
    qty INT NOT NULL CHECK (qty > 0),
    price DECIMAL(10,2) NOT NULL CHECK (price >= 0),
    status order_item_status_enum NOT NULL,
    PRIMARY KEY (order_id, item_number),
    FOREIGN KEY (order_id) REFERENCES customer_order(order_id) ON DELETE CASCADE ON UPDATE CASCADE,
    FOREIGN KEY (recipe_id, recipe_version) REFERENCES recipe(recipe_id, version) ON DELETE RESTRICT ON UPDATE CASCADE
);

-- Выбор начинки/E18
CREATE TABLE order_item_topping (
    order_id UUID NOT NULL,
    item_number INT NOT NULL,
    topping_id UUID NOT NULL REFERENCES topping(topping_id) ON DELETE RESTRICT ON UPDATE CASCADE,
    PRIMARY KEY (order_id, item_number, topping_id),
    FOREIGN KEY (order_id, item_number) REFERENCES order_item(order_id, item_number) ON DELETE CASCADE ON UPDATE CASCADE
);

-- Списание/E14
CREATE TABLE write_off (
    write_off_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    semi_finished_id UUID NOT NULL,
    batch_number INT NOT NULL,
    sales_point_id UUID NOT NULL REFERENCES sales_point(sales_point_id) ON DELETE RESTRICT ON UPDATE CASCADE,
    write_off_number INT NOT NULL UNIQUE,
    write_off_time TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    qty INT NOT NULL CHECK (qty > 0),
    reason write_off_reason_enum NOT NULL,
    responsible VARCHAR(50),
    FOREIGN KEY (semi_finished_id, batch_number) REFERENCES product_batch(semi_finished_id, batch_number) ON DELETE RESTRICT ON UPDATE CASCADE
);

-- Проверка качества/E15
CREATE TABLE quality_check (
    check_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    sales_point_id UUID NOT NULL REFERENCES sales_point(sales_point_id) ON DELETE RESTRICT ON UPDATE CASCADE,
    check_time TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    check_type check_type_enum NOT NULL,
    result check_result_enum NOT NULL,
    responsible VARCHAR(50) NOT NULL,
    comment TEXT
);

-- Нарушение/E16
CREATE TABLE violation (
    violation_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    sales_point_id UUID NOT NULL REFERENCES sales_point(sales_point_id) ON DELETE RESTRICT ON UPDATE CASCADE,
    franchisee_id UUID NOT NULL REFERENCES franchisee(franchisee_id) ON DELETE RESTRICT ON UPDATE CASCADE,
    check_id UUID NOT NULL REFERENCES quality_check(check_id) ON DELETE RESTRICT ON UPDATE CASCADE,
    violation_time TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    type VARCHAR(50) NOT NULL,
    description TEXT,
    criticality criticality_enum NOT NULL,
    resolution_status resolution_status_enum NOT NULL DEFAULT 'открыто'
);

-- Локальная цена/E17
CREATE TABLE local_price (
    sales_point_id UUID NOT NULL REFERENCES sales_point(sales_point_id) ON DELETE CASCADE ON UPDATE CASCADE,
    product_id UUID NOT NULL REFERENCES base_product(product_id) ON DELETE CASCADE ON UPDATE CASCADE,
    value DECIMAL(10,2) NOT NULL CHECK (value >= 0),
    start_date DATE NOT NULL,
    end_date DATE,
    reason VARCHAR(100),
    PRIMARY KEY (sales_point_id, product_id)
);

-- Рецептура договора/E19
CREATE TABLE contract_recipe (
    contract_id UUID NOT NULL REFERENCES franchise_contract(contract_id) ON DELETE CASCADE ON UPDATE CASCADE,
    recipe_id UUID NOT NULL,
    version INT NOT NULL,
    PRIMARY KEY (contract_id, recipe_id, version),
    FOREIGN KEY (recipe_id, version) REFERENCES recipe(recipe_id, version) ON DELETE RESTRICT ON UPDATE CASCADE
);