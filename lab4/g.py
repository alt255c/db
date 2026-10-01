import psycopg2
import psycopg2.extras
from faker import Faker
import logging
import random
from datetime import datetime, timedelta


class FranchiseDBFiller:
    def __init__(self, db_config):
        self.fake = Faker('ru_RU')
        self.db_config = db_config
        self.conn = None
        self.cursor = None
        self.sales_points = []
        self.franchisees = []
        self.products = []
        self.toppings = []
        self.semi_finished = []
        self.recipes = []
        self.incompatibilities = []
        self.batch_stocks = {}
        self.batch_points = {}

    def connect(self):
        try:
            self.conn = psycopg2.connect(**self.db_config)
            psycopg2.extras.register_uuid()
            self.cursor = self.conn.cursor()
            logging.info("Успешное подключение к БД")
        except Exception as e:
            logging.error(f"Ошибка подключения: {e}")
            raise

    def close(self):
        if self.cursor:
            self.cursor.close()
        if self.conn:
            self.conn.close()
        logging.info("Соединение закрыто")

    def fetch_dictionary(self):
        logging.info("Загрузка справочников...")
        self.cursor.execute("SELECT franchisee_id, inn FROM franchisee")
        self.franchisees = [{'id': r[0], 'inn': r[1]} for r in self.cursor.fetchall()]

        self.cursor.execute("SELECT sales_point_id, franchisee_id FROM sales_point")
        self.sales_points = [{'id': r[0], 'franchisee_id': r[1]} for r in self.cursor.fetchall()]

        self.cursor.execute("SELECT product_id, name, base_price FROM base_product WHERE status = 'в продаже'")
        self.products = [{'id': r[0], 'name': r[1], 'price': float(r[2])} for r in self.cursor.fetchall()]

        self.cursor.execute("SELECT topping_id, name, surcharge FROM topping WHERE status = 'в продаже'")
        self.toppings = [{'id': r[0], 'name': r[1], 'surcharge': float(r[2])} for r in self.cursor.fetchall()]

        self.cursor.execute("SELECT semi_finished_id, name FROM semi_finished_product")
        self.semi_finished = [{'id': r[0], 'name': r[1]} for r in self.cursor.fetchall()]

        self.cursor.execute("SELECT recipe_id, version, product_id FROM recipe WHERE status = 'действует'")
        self.recipes = [{'id': r[0], 'version': r[1], 'product_id': r[2]} for r in self.cursor.fetchall()]

        self.cursor.execute(
            "SELECT product_id, topping_id, restriction_type FROM incompatibility_rule WHERE status = 'действует'"
        )
        self.incompatibilities = [
            {'product_id': r[0], 'topping_id': r[1], 'type': r[2]} for r in self.cursor.fetchall()
        ]

        self.cursor.execute(
            "SELECT semi_finished_id, batch_number, current_stock, sales_point_id FROM product_batch"
        )
        for r in self.cursor.fetchall():
            self.batch_stocks[(r[0], r[1])] = r[2]
            self.batch_points[(r[0], r[1])] = r[3]

        logging.info(
            f"Загружено: {len(self.sales_points)} точек, "
            f"{len(self.products)} товаров, {len(self.toppings)} начинок."
        )

    def fill_supplies_and_batches(self, num_supplies=20):
        logging.info("Генерация поставок и партий...")
        supply_ids = []

        for i in range(num_supplies):
            sp = random.choice(self.sales_points)
            sent_qty = random.randint(10, 100)
            is_discrepancy = random.random() < 0.3
            received_qty = sent_qty - random.randint(1, 5) if is_discrepancy else sent_qty
            status = 'расхождение' if is_discrepancy else 'принята'

            self.cursor.execute("""
                INSERT INTO supply (sales_point_id, supply_number, arrival_date, supplier_name, 
                                    sent_qty, received_qty, status) 
                VALUES (%s, %s, %s, %s, %s, %s, %s::supply_status_enum) RETURNING supply_id
            """, (sp['id'], 1000 + i, self.fake.date_this_year(), self.fake.company(),
                  sent_qty, received_qty, status))
            supply_id = self.cursor.fetchone()[0]
            supply_ids.append((supply_id, sp['id'], received_qty))

            if is_discrepancy:
                self.cursor.execute("""
                    INSERT INTO discrepancy_act (supply_id, act_number, act_date, discrepancies_list, confirmation_status)
                    VALUES (%s, %s, %s, %s, %s::act_confirmation_enum)
                """, (supply_id, 5000 + i, self.fake.date_this_year(),
                      f"Недовложено {sent_qty - received_qty} кг теста",
                      random.choice(['не подтверждён', 'подтверждён'])))

        for supply_id, sp_id, qty in supply_ids:
            sf = random.choice(self.semi_finished)
            batch_num = random.randint(1, 9999)
            while (sf['id'], batch_num) in self.batch_stocks:
                batch_num = random.randint(1, 9999)

            expiry = self.fake.date_between(start_date='+10d', end_date='+30d')

            self.cursor.execute("""
                INSERT INTO product_batch (semi_finished_id, batch_number, sales_point_id, supply_id, 
                                           arrival_date, initial_qty, expiry_date, current_stock, status)
                VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s::batch_status_enum)
            """, (sf['id'], batch_num, sp_id, supply_id, self.fake.date_this_year(),
                  qty, expiry, qty, 'на хранении'))

            self.batch_stocks[(sf['id'], batch_num)] = qty
            self.batch_points[(sf['id'], batch_num)] = sp_id

        self.conn.commit()
        logging.info(f"Создано {num_supplies} поставок и партий.")

    def fill_orders_and_items(self, num_orders=50):
        logging.info("Генерация заказов...")

        for i in range(num_orders):
            sp = random.choice(self.sales_points)
            order_time = self.fake.date_time_this_year()

            self.cursor.execute("""
                INSERT INTO customer_order (sales_point_id, order_number, order_time, customer_name, 
                                            total_cost, status)
                VALUES (%s, %s, %s, %s, %s, %s::order_status_enum) RETURNING order_id
            """, (sp['id'], 8000 + i, order_time, self.fake.name(), 0.0, 'выдан'))
            order_id = self.cursor.fetchone()[0]

            num_items = random.randint(1, 3)
            total_cost = 0.0

            for j in range(num_items):
                prod = random.choice(self.products)
                valid_recipes = [r for r in self.recipes if r['product_id'] == prod['id']]
                if not valid_recipes:
                    continue
                recipe = random.choice(valid_recipes)

                qty = random.randint(1, 3)
                price = prod['price']
                total_cost += price * qty

                self.cursor.execute("""
                    INSERT INTO order_item (order_id, item_number, product_id, recipe_id, recipe_version, 
                                            qty, price, status)
                    VALUES (%s, %s, %s, %s, %s, %s, %s, %s::order_item_status_enum)
                """, (order_id, j + 1, prod['id'], recipe['id'], recipe['version'],
                      qty, price, 'приготовлена'))

                forbidden_toppings = set()
                for rule in self.incompatibilities:
                    if rule['product_id'] == prod['id'] and rule['type'] == 'запрет сочетания':
                        forbidden_toppings.add(rule['topping_id'])

                available_toppings = [t for t in self.toppings if t['id'] not in forbidden_toppings]

                num_toppings = random.randint(0, min(2, len(available_toppings)))
                chosen_toppings = random.sample(available_toppings, num_toppings)

                for t in chosen_toppings:
                    self.cursor.execute("""
                        INSERT INTO order_item_topping (order_id, item_number, topping_id)
                        VALUES (%s, %s, %s)
                    """, (order_id, j + 1, t['id']))
                    total_cost += t['surcharge'] * qty

            self.cursor.execute("""
                UPDATE customer_order SET total_cost = %s WHERE order_id = %s
            """, (total_cost, order_id))

        self.conn.commit()
        logging.info(f"Создано {num_orders} заказов с позициями и начинками.")

    def fill_write_offs(self, num_write_offs=30):
        logging.info("Генерация списаний (с контролем остатков)...")

        available_batches = [k for k, v in self.batch_stocks.items() if v > 0]
        if not available_batches:
            logging.warning("Нет остатков на складах для списания!")
            return

        for i in range(num_write_offs):
            if not available_batches:
                break

            batch_key = random.choice(available_batches)
            current_stock = self.batch_stocks[batch_key]
            sp_id = self.batch_points[batch_key]

            write_off_qty = random.randint(1, min(5, current_stock))

            reason = random.choice(['производственное списание', 'порча', 'истёк срок'])

            self.cursor.execute("""
                INSERT INTO write_off (semi_finished_id, batch_number, sales_point_id, write_off_number, 
                                       write_off_time, qty, reason)
                VALUES (%s, %s, %s, %s, %s, %s, %s::write_off_reason_enum)
            """, (batch_key[0], batch_key[1], sp_id, 3000 + i,
                  self.fake.date_time_this_year(), write_off_qty, reason))

            new_stock = current_stock - write_off_qty
            new_status = 'исчерпана' if new_stock == 0 else 'на хранении'

            self.cursor.execute("""
                UPDATE product_batch 
                SET current_stock = %s, status = %s::batch_status_enum
                WHERE semi_finished_id = %s AND batch_number = %s
            """, (new_stock, new_status, batch_key[0], batch_key[1]))

            self.batch_stocks[batch_key] = new_stock
            if new_stock == 0:
                available_batches.remove(batch_key)

        self.conn.commit()
        logging.info(f"Сделано {num_write_offs} списаний. Остатки обновлены.")

    def fill_checks_and_violations(self, num_checks=10):
        logging.info("Генерация проверок качества и нарушений...")

        for i in range(num_checks):
            sp = random.choice(self.sales_points)
            check_type = random.choice(['плановая', 'внеплановая'])
            result = random.choice(['пройдена', 'выявлены нарушения'])

            self.cursor.execute("""
                INSERT INTO quality_check (sales_point_id, check_time, check_type, result, responsible)
                VALUES (%s, %s, %s::check_type_enum, %s::check_result_enum, %s) RETURNING check_id
            """, (sp['id'], self.fake.date_time_this_year(), check_type, result, self.fake.name()))
            check_id = self.cursor.fetchone()[0]

            if result == 'выявлены нарушения':
                num_violations = random.randint(1, 3)
                for _ in range(num_violations):
                    self.cursor.execute("""
                        INSERT INTO violation (sales_point_id, franchisee_id, check_id, violation_time, 
                                               type, description, criticality, resolution_status)
                        VALUES (%s, %s, %s, %s, %s, %s, %s::criticality_enum, %s::resolution_status_enum)
                    """, (sp['id'], sp['franchisee_id'], check_id, self.fake.date_time_this_year(),
                          random.choice(['Санитария', 'Техника безопасности', 'Кассовая дисциплина']),
                          self.fake.sentence(nb_words=6),
                          random.choice(['низкая', 'средняя', 'высокая']),
                          random.choice(['открыто', 'в работе', 'устранено'])))

        self.conn.commit()
        logging.info(f"Создано {num_checks} проверок и связанных нарушений.")

    def generate_all(self):
        self.connect()
        try:
            self.fetch_dictionary()
            self.fill_supplies_and_batches(num_supplies=100)
            self.fill_orders_and_items(num_orders=500)
            self.fill_write_offs(num_write_offs=200)
            self.fill_checks_and_violations(num_checks=40)
            logging.info("=== ВСЕ ТЕСТОВЫЕ ДАННЫЕ УСПЕШНО СГЕНЕРИРОВАНЫ ===")
        except Exception as e:
            self.conn.rollback()
            logging.error(f"Критическая ошибка, транзакция откатана: {e}")
            raise
        finally:
            self.close()


if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')

    db_config = {
        'dbname': 'franchise_db',
        'user': 'postgres',
        'password': '',
        'host': 'localhost',
        'port': 5432
    }

    filler = FranchiseDBFiller(db_config)
    filler.generate_all()