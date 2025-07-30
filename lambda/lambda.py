import boto3
import os

rds = boto3.client("rds-data")

def handler(event, context):
    sql_commands = [
        "CREATE EXTENSION IF NOT EXISTS vector;",
        "CREATE ROLE bedrock_user WITH PASSWORD 'password' LOGIN;",
        "GRANT ALL ON SCHEMA public TO bedrock_user;",

        "CREATE TABLE public.bedrock_kb ("
        "id uuid PRIMARY KEY, "
        "embedding vector(1024), "
        "chunks text, "
        "metadata json, "
        "custom_metadata jsonb"
        ");",

        "CREATE INDEX ON public.bedrock_kb USING hnsw (embedding vector_cosine_ops);",
        "CREATE INDEX ON public.bedrock_kb USING hnsw (embedding vector_cosine_ops) WITH (ef_construction=256);",
        "CREATE INDEX ON public.bedrock_kb USING gin (to_tsvector('simple', chunks));",
        "CREATE INDEX ON public.bedrock_kb USING gin (custom_metadata);"
    ]

    for sql in sql_commands:
        response = rds.execute_statement(
            resourceArn=os.environ['DB_CLUSTER_ARN'],
            secretArn=os.environ['DB_SECRET_ARN'],
            database='postgres',
            sql=sql
        )