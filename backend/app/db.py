import psycopg2
import time

def insert_message(text, retries=3, delay=2):
    for attempt in range(retries):
        try:
            conn = psycopg2.connect(
                host="miniapp_db",
                dbname="miniapp_db",
                user="miniapp_user",
                password="miniapp_password"
            )
            cur = conn.cursor()
            cur.execute("INSERT INTO messages (content) VALUES (%s);", (text,))
            conn.commit()
            cur.close()
            conn.close()
            return
        except psycopg2.OperationalError as e:
            print(f"DB connect failed: {e}")
            time.sleep(delay)
    raise Exception("Could not connect to DB after retries")