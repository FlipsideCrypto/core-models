DBT_TARGET ?= dev

streamline_functions:
	rm -f package-lock.yml && dbt clean && dbt deps
	dbt run -s livequery_models.deploy.core --vars '{"UPDATE_UDFS_AND_SPS":True}' -t $(DBT_TARGET)
	dbt run-operation fsc_utils.create_evm_streamline_udfs --vars '{"UPDATE_UDFS_AND_SPS":True}' -t $(DBT_TARGET)

streamline_tables:
	rm -f package-lock.yml && dbt clean && dbt deps
ifeq ($(findstring dev,$(DBT_TARGET)),dev)
	dbt run -m models/bronze/core --vars '{"STREAMLINE_USE_DEV_FOR_EXTERNAL_TABLES":True}' -t $(DBT_TARGET)
else
	dbt run -m models/bronze/core -t $(DBT_TARGET)
endif
	dbt run -m models/streamline models/silver/utilities/silver__number_sequence.sql --full-refresh -t $(DBT_TARGET)

streamline_requests:
	rm -f package-lock.yml && dbt clean && dbt deps
	dbt run -m tag:streamline_core_complete tag:streamline_core_realtime --vars '{"STREAMLINE_INVOKE_STREAMS":True}' -t $(DBT_TARGET)

.PHONY: streamline_functions streamline_tables streamline_requests
