#!/bin/bash
source .env
spin deploy --variable openapi_key="${SPIN_VARIABLE_OPENAPI_KEY}" --variable client_id="${SPIN_VARIABLE_CLIENT_ID}" --variable private_key="${SPIN_VARIABLE_PRIVATE_KEY}" --variable user_agent="${SPIN_VARIABLE_USER_AGENT}" --variable app_id="${SPIN_VARIABLE_APP_ID}"