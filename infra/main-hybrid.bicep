targetScope = 'subscription'

@minLength(1)
@maxLength(64)
@description('Name of the environment that can be used as part of naming resource convention, the name of the resource group for your application will use this name, prefixed with rg-')
param environmentName string

@minLength(1)
@description('The location used for all deployed resources')
param location string

@description('Id of the principal to assign application roles')
param principalId string = ''

var tags = {
  'azd-env-name': environmentName
}

resource rg 'Microsoft.Resources/resourceGroups@2022-09-01' = {
  name: 'rg-${environmentName}'
  location: location
  tags: tags
}

module services 'services.bicep' = {
  scope: rg
  name: 'services'
  params: {
    location: location
    resourceGroupName: rg.name
  }
}

module user_roles 'app-roles.bicep' = {
  scope: rg
  name: 'user-roles'
  params: {
    resourceGroupName: rg.name
    principalId: principalId
    principalType: 'User'
    appConfigName: services.outputs.APP_CONFIG_APPCONFIGNAME
    appSecretsName: services.outputs.APP_SECRETS_VAULTNAME
    messageBusName: services.outputs.MESSAGE_BUS_SERVICEBUSNAME
  }
}

output APP_CONFIG_APPCONFIGENDPOINT string = services.outputs.APP_CONFIG_APPCONFIGENDPOINT
output APP_SECRETS_VAULTURI string = services.outputs.APP_SECRETS_VAULTURI
output ASB_MESSAGING_SERVICEBUSENDPOINT string = services.outputs.MESSAGE_BUS_SERVICEBUSENDPOINT
