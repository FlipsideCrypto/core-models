## Profile Set Up

#### Use the following within profiles.yml
----

```yml
{{ chain }}: -- replace {{ chain }}/{{ CHAIN }} with the profile or name from, remove this comment in your yml
  target: dev
  outputs:
    dev:
      type: snowflake
      account: <ACCOUNT>
      role: INTERNAL_DEV
      user: <USERNAME>
      authenticator: externalbrowser
      region: us-east-1
      database: {{ CHAIN }}_DEV
      warehouse: DBT
      schema: silver
      threads: 4
      client_session_keep_alive: False
      query_tag: dbt_<user>_dev

    prod:
      type: snowflake
      account: <ACCOUNT>
      role: DBT_CLOUD_{{ CHAIN }}
      user: <USERNAME>
      authenticator: externalbrowser
      region: us-east-1
      database: {{ CHAIN }}
      warehouse: DBT_CLOUD_{{ CHAIN }}
      schema: silver
      threads: 4
      client_session_keep_alive: False
      query_tag: dbt_<user>_dev
```

### Common DBT Run Variables

The following variables can be used to control various aspects of the dbt run. Use them with the `--vars` flag when running dbt commands.

| Variable | Description | Example Usage |
|----------|-------------|---------------|
| `UPDATE_UDFS_AND_SPS` | Update User Defined Functions and Stored Procedures. By default, this is set to False | `--vars '{"UPDATE_UDFS_AND_SPS":true}'` |
| `STREAMLINE_INVOKE_STREAMS` | Invoke Streamline processes. By default, this is set to False | `--vars '{"STREAMLINE_INVOKE_STREAMS":true}'` |
| `STREAMLINE_USE_DEV_FOR_EXTERNAL_TABLES` | Use development environment for external tables. By default, this is set to False | `--vars '{"STREAMLINE_USE_DEV_FOR_EXTERNAL_TABLES":true}'` |
| `HEAL_CURATED_MODEL` | Heal specific curated models. By default, this is set to an empty array []. See more below. | `--vars '{"HEAL_CURATED_MODEL":["axelar","across","celer_cbridge"]}'` |
| `UPDATE_SNOWFLAKE_TAGS` | Control updating of Snowflake tags. By default, this is set to False | `--vars '{"UPDATE_SNOWFLAKE_TAGS":false}'` |
| `START_GHA_TASKS` | Start GitHub Actions tasks. By default, this is set to False | `--vars '{"START_GHA_TASKS":true}'` |

#### Example Commands

1. Update UDFs and SPs:
   ```
   dbt run --vars '{"UPDATE_UDFS_AND_SPS":true}' -m ...
   ```

2. Invoke Streamline and use dev for external tables:
   ```
   dbt run --vars '{"STREAMLINE_INVOKE_STREAMS":true,"STREAMLINE_USE_DEV_FOR_EXTERNAL_TABLES":true}' -m ...
   ```

3. Heal specific curated models:
   ```
   dbt run --vars '{"HEAL_CURATED_MODEL":["axelar","across","celer_cbridge"]}' -m ...
   ```

4. Update Snowflake tags for a specific model:
   ```
   dbt run --vars '{"UPDATE_SNOWFLAKE_TAGS":true}' -s models/silver/utilities/silver__number_sequence.sql
   ```

5. Start GHA tasks:
   ```
   dbt seed -s github_actions__workflows && dbt run -m models/github_actions --full-refresh && dbt run-operation fsc_utils.create_gha_tasks --vars '{"START_GHA_TASKS":True}'
   ```

> Note: Replace `-m ...` with appropriate model selections or tags as needed for your project structure.

### Healing Curated Models

To reload records in a curated complete table without a full-refresh, such as `silver_bridge.complete_bridge_activity`:
* HEAL_CURATED_MODEL
Default is an empty array []
When item is included in var array [], incremental logic will be skipped for that CTE / code block  
When item is not included in var array [] or does not match specified item in model, incremental logic will apply
Example set up: `{% if is_incremental() and 'axelar' not in var('HEAL_CURATED_MODEL') %}`

* Usage:
Single CTE: dbt run --vars '{"HEAL_CURATED_MODEL":"axelar"}' -m ...
Multiple CTEs: dbt run --vars '{"HEAL_CURATED_MODEL":["axelar","across","celer_cbridge"]}' -m ...

## Applying Model Tags

### Database / Schema level tags

Database and schema tags are applied via the `add_database_or_schema_tags` macro.  These tags are inherited by their downstream objects.  To add/modify tags call the appropriate tag set function within the macro.

```
{{ set_database_tag_value('SOME_DATABASE_TAG_KEY','SOME_DATABASE_TAG_VALUE') }}
{{ set_schema_tag_value('SOME_SCHEMA_TAG_KEY','SOME_SCHEMA_TAG_VALUE') }}
```

### Model tags

To add/update a model's snowflake tags, add/modify the `meta` model property under `config`.  Only table level tags are supported at this time via DBT.

```
{{ config(
    ...,
    meta={
        'database_tags':{
            'table': {
                'PURPOSE': 'SOME_PURPOSE'
            }
        }
    },
    ...
) }}
```

By default, model tags are pushed to Snowflake on each load. You can disable this by setting the `UPDATE_SNOWFLAKE_TAGS` project variable to `False` during a run.

```
dbt run --vars '{"UPDATE_SNOWFLAKE_TAGS":False}' -s models/silver/utilities/silver__number_sequence.sql
```

### Querying for existing tags on a model in snowflake

```
select *
from table({{ chain }}.information_schema.tag_references('{{ chain }}.core.fact_blocks', 'table'));
```