DBT_TARGET ?= dev

deploy_streamline_functions:
	rm -f package-lock.yml && dbt clean && dbt deps
	dbt run -s livequery_models.deploy.core --vars '{"UPDATE_UDFS_AND_SPS":True}' -t $(DBT_TARGET)
	dbt run-operation fsc_utils.create_evm_streamline_udfs --vars '{"UPDATE_UDFS_AND_SPS":True}' -t $(DBT_TARGET)

cleanup_time:
	rm -f package-lock.yml && dbt clean && dbt deps

deploy_streamline_tables:
	rm -f package-lock.yml && dbt clean && dbt deps
ifeq ($(findstring dev,$(DBT_TARGET)),dev)
	dbt run -m models/bronze/core --vars '{"STREAMLINE_USE_DEV_FOR_EXTERNAL_TABLES":True}' -t $(DBT_TARGET)
else
	dbt run -m models/bronze/core -t $(DBT_TARGET)
endif
	dbt run -m models/streamline models/silver/utilities/silver__number_sequence.sql --full-refresh -t $(DBT_TARGET)

deploy_streamline_requests:
	rm -f package-lock.yml && dbt clean && dbt deps
	dbt run -m tag:streamline_core_complete tag:streamline_core_realtime --vars '{"STREAMLINE_INVOKE_STREAMS":True}' -t $(DBT_TARGET)

deploy_github_actions:
	dbt run -s livequery_models.deploy.marketplace.github --vars '{"UPDATE_UDFS_AND_SPS":True}' -t $(DBT_TARGET)
	dbt seed -s github_actions__workflows -t $(DBT_TARGET)
	dbt run -m models/github_actions --full-refresh -t $(DBT_TARGET)
ifeq ($(findstring dev,$(DBT_TARGET)),dev)
	dbt run-operation fsc_utils.create_gha_tasks --vars '{"START_GHA_TASKS":False}' -t $(DBT_TARGET)
else
	dbt run-operation fsc_utils.create_gha_tasks --vars '{"START_GHA_TASKS":True}' -t $(DBT_TARGET)
endif

.PHONY: deploy_streamline_functions deploy_streamline_tables deploy_streamline_requests deploy_github_actions cleanup_time
