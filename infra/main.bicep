targetScope = 'subscription'

@minLength(1)
@maxLength(64)
@description('Name of the environment that can be used as part of naming resource convention, the name of the resource group for your application will use this name, prefixed with rg-')
param environmentName string

@description('True to provision only the resources required for local development, false (the default) to provision all the resources required for the application to run in the cloud)')
param hybridEnvironment bool = false

@minLength(1)
@description('The location used for all deployed resources')
param location string

@description('Id of the principal to assign application roles')
param principalId string = ''

module hybrid 'main-hybrid.bicep' = if (hybridEnvironment) {
  name: 'hybrid-deployment'
  params: {
    environmentName: environmentName
    location: location
    principalId: principalId
  }
}

module remote 'main-remote.bicep' = if (!hybridEnvironment) {
  name: 'remote-deployment'
  params: {
    environmentName: environmentName
    location: location
  }
}

output MANAGED_IDENTITY_CLIENT_ID string = !hybridEnvironment ? remote.outputs.MANAGED_IDENTITY_CLIENT_ID : ''
output MANAGED_IDENTITY_NAME string = !hybridEnvironment ? remote.outputs.MANAGED_IDENTITY_NAME : ''
output AZURE_LOG_ANALYTICS_WORKSPACE_NAME string = !hybridEnvironment ? remote.outputs.AZURE_LOG_ANALYTICS_WORKSPACE_NAME : ''
output AZURE_CONTAINER_REGISTRY_ENDPOINT string = !hybridEnvironment ? remote.outputs.AZURE_CONTAINER_REGISTRY_ENDPOINT : ''
output AZURE_CONTAINER_REGISTRY_MANAGED_IDENTITY_ID string = !hybridEnvironment ? remote.outputs.AZURE_CONTAINER_REGISTRY_MANAGED_IDENTITY_ID : ''
output AZURE_CONTAINER_REGISTRY_NAME string = !hybridEnvironment ? remote.outputs.AZURE_CONTAINER_REGISTRY_NAME : ''
output AZURE_CONTAINER_APPS_ENVIRONMENT_NAME string = !hybridEnvironment ? remote.outputs.AZURE_CONTAINER_APPS_ENVIRONMENT_NAME : ''
output AZURE_CONTAINER_APPS_ENVIRONMENT_ID string = !hybridEnvironment ? remote.outputs.AZURE_CONTAINER_APPS_ENVIRONMENT_ID : ''
output AZURE_CONTAINER_APPS_ENVIRONMENT_DEFAULT_DOMAIN string = !hybridEnvironment ? remote.outputs.AZURE_CONTAINER_APPS_ENVIRONMENT_DEFAULT_DOMAIN : ''

output APP_CONFIG_APPCONFIGENDPOINT string = hybridEnvironment ? hybrid.outputs.APP_CONFIG_APPCONFIGENDPOINT : remote.outputs.APP_CONFIG_APPCONFIGENDPOINT
output APP_SECRETS_VAULTURI string = hybridEnvironment ? hybrid.outputs.APP_SECRETS_VAULTURI : remote.outputs.APP_SECRETS_VAULTURI
output ASB_MESSAGING_SERVICEBUSENDPOINT string = hybridEnvironment ? hybrid.outputs.ASB_MESSAGING_SERVICEBUSENDPOINT : remote.outputs.ASB_MESSAGING_SERVICEBUSENDPOINT
