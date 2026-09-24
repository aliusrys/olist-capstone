"""Загрузка 9 CSV-файлов Olist в SQLite по схеме из sql/01_schema.sql.

Запуск из корня репозитория:
    python src/build_database.py
"""
from pathlib import Path
import sqlite3

import pandas as pd

ROOT = Path(__file__).resolve().parents[1]
RAW = ROOT / "data" / "raw"
DB_PATH = ROOT / "data" / "olist.db"
SCHEMA = ROOT / "sql" / "01_schema.sql"

# CSV-файл -> таблица в БД
TABLES = {
    "olist_customers_dataset.csv": "customers",
    "olist_sellers_dataset.csv": "sellers",
    "product_category_name_translation.csv": "category_translation",
    "olist_products_dataset.csv": "products",
    "olist_orders_dataset.csv": "orders",
    "olist_order_items_dataset.csv": "order_items",
    "olist_order_payments_dataset.csv": "order_payments",
    "olist_order_reviews_dataset.csv": "order_reviews",
    "olist_geolocation_dataset.csv": "geolocation",
}

# Почтовые префиксы читаем как строки, иначе теряются ведущие нули ("01037" -> 1037)
STR_COLS = {
    "customer_zip_code_prefix": str,
    "seller_zip_code_prefix": str,
    "geolocation_zip_code_prefix": str,
}


def build(db_path: Path = DB_PATH) -> dict:
    missing = [f for f in TABLES if not (RAW / f).exists()]
    if missing:
        raise FileNotFoundError(
            f"Нет файлов в {RAW}: {missing}. Скачайте датасет с Kaggle (см. README)."
        )

    con = sqlite3.connect(db_path)
    con.executescript(SCHEMA.read_text(encoding="utf-8"))

    counts = {}
    for csv_name, table in TABLES.items():
        df = pd.read_csv(RAW / csv_name, dtype=STR_COLS)
        # В customers/sellers индексы сохранены без ведущих нулей ("9790"),
        # а в geolocation — с ними ("09790"). Приводим все к 5 символам.
        for col in df.columns:
            if col.endswith("zip_code_prefix"):
                df[col] = df[col].str.zfill(5)
        # вставляем в заранее созданные таблицы, чтобы сохранить ключи и типы
        df.to_sql(table, con, if_exists="append", index=False, chunksize=50_000)
        counts[table] = len(df)
        print(f"{table:<22} {len(df):>9,} строк")

    con.commit()

    # Признаки собираем прямо в БД: промежуточные агрегаты + финальная витрина
    for script in ("02_feature_tables.sql", "03_feature_mart.sql"):
        con.executescript((ROOT / "sql" / script).read_text(encoding="utf-8"))
    n = con.execute("SELECT COUNT(*) FROM order_features").fetchone()[0]
    print(f"\norder_features (витрина для модели): {n:,} строк")

    # проверка ссылочной целостности
    violations = con.execute("PRAGMA foreign_key_check").fetchall()
    print(f"\nНарушений внешних ключей: {len(violations)}")
    con.close()
    return counts


if __name__ == "__main__":
    build()
