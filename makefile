streamline_functions_dev:
	rm -f package-lock.yml && dbt clean && dbt deps
	dbt run -s livequery_models.deploy.core --vars '{"UPDATE_UDFS_AND_SPS":True}' -t dev
	dbt run-operation fsc_utils.create_evm_streamline_udfs --vars '{"UPDATE_UDFS_AND_SPS":True}' -t dev

streamline_tables_dev:
	dbt clean && dbt deps
	dbt run -m models/bronze/core --vars '{"STREAMLINE_USE_DEV_FOR_EXTERNAL_TABLES":True}' -t dev
	dbt run -m models/streamline models/silver/utilities/silver__number_sequence.sql --full-refresh -t dev

streamline_requests_dev:
	dbt clean && dbt deps
	dbt run -m tag:streamline_core_complete tag:streamline_core_realtime --vars '{"STREAMLINE_INVOKE_STREAMS":True}' -t dev

.PHONY: streamline_functions_dev streamline_tables_dev streamline_requests_dev
