@description('The name of the Function App')
param functionAppName string

@description('The name of the App Service Plan')
param appServicePlanName string

@description('The name of the Storage Account')
param storageAccountName string

@description('The name of the Cosmos DB Account')
param cosmosDbAccountName string

@description('Your public IP address allowed for access')
param myIp string = '203.0.113.1'

@description('The name of the Virtual Network (VNet)')
param vnetName string = 'myVNet'

@description('The name of the Subnet')
param subnetName string = 'functionSubnet'

@description('The name of the Network Security Group (NSG)')
param nsgName string = 'functionAppNSG'

@description('Location for all resources')
param location string = resourceGroup().location

// Storage Account
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: storageAccountName
  location: location
  kind: 'StorageV2'
  sku: {
    name: 'Standard_LRS'
  }
}

// Cosmos DB Account
resource cosmosDb 'Microsoft.DocumentDB/databaseAccounts@2023-03-15' = {
  name: cosmosDbAccountName
  location: location
  properties: {
    locations: [
      {
        locationName: location
        failoverPriority: 0
      }
    ]
    databaseAccountOfferType: 'Standard'
  }
}

// Virtual Network and Subnet
resource vnet 'Microsoft.Network/virtualNetworks@2023-02-01' = {
  name: vnetName
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: ['10.0.0.0/16']
    }
    subnets: [
      {
        name: subnetName
        properties: {
          addressPrefix: '10.0.1.0/24'
          networkSecurityGroup: {
            id: nsg.id
          }
        }
      }
    ]
  }
}

// Network Security Group
resource nsg 'Microsoft.Network/networkSecurityGroups@2023-02-01' = {
  name: nsgName
  location: location
  properties: {
    securityRules: [
      {
        name: 'AllowInboundFromMyIP'
        properties: {
          priority: 100
          direction: 'Inbound'
          access: 'Allow'
          protocol: '*'
          sourceAddressPrefix: myIp
          destinationAddressPrefix: '*'
          sourcePortRange: '*'
          destinationPortRange: '*'
        }
      }
      {
        name: 'DenyAllInbound'
        properties: {
          priority: 200
          direction: 'Inbound'
          access: 'Deny'
          protocol: '*'
          sourceAddressPrefix: '*'
          destinationAddressPrefix: '*'
          sourcePortRange: '*'
          destinationPortRange: '*'
        }
      }
      {
        name: 'DenyOutboundToInternet'
        properties: {
          priority: 100
          direction: 'Outbound'
          access: 'Deny'
          protocol: '*'
          sourceAddressPrefix: '*'
          destinationAddressPrefix: 'Internet'
          sourcePortRange: '*'
          destinationPortRange: '*'
        }
      }
      {
        name: 'AllowOutboundToAzure'
        properties: {
          priority: 200
          direction: 'Outbound'
          access: 'Allow'
          protocol: '*'
          sourceAddressPrefix: '*'
          destinationAddressPrefix: 'AzureCloud'
          sourcePortRange: '*'
          destinationPortRange: '*'
        }
      }
    ]
  }
}

// Private Endpoint for Storage
resource storagePrivateEndpoint 'Microsoft.Network/privateEndpoints@2023-02-01' = {
  name: '${storageAccountName}-pe'
  location: location
  properties: {
    subnet: {
      id: resourceId('Microsoft.Network/virtualNetworks/subnets', vnetName, subnetName)
    }
    privateLinkServiceConnections: [
      {
        name: 'storageConnection'
        properties: {
          privateLinkServiceId: storageAccount.id
          groupIds: [
            'blob'
            'queue'
          ]
        }
      }
    ]
  }
}

// Private Endpoint for Cosmos DB
resource cosmosDbPrivateEndpoint 'Microsoft.Network/privateEndpoints@2023-02-01' = {
  name: '${cosmosDbAccountName}-pe'
  location: location
  properties: {
    subnet: {
      id: resourceId('Microsoft.Network/virtualNetworks/subnets', vnetName, subnetName)
    }
    privateLinkServiceConnections: [
      {
        name: 'cosmosConnection'
        properties: {
          privateLinkServiceId: cosmosDb.id
          groupIds: [
            'Sql'
          ]
        }
      }
    ]
  }
}

// Private DNS Zones for Storage and Cosmos DB
resource privateDnsZoneStorage 'Microsoft.Network/privateDnsZones@2023-02-01' = {
  name: 'privatelink.blob.core.windows.net'
  location: 'global'
}

resource privateDnsZoneCosmos 'Microsoft.Network/privateDnsZones@2023-02-01' = {
  name: 'privatelink.documents.azure.com'
  location: 'global'
}

// DNS Zone Links
resource privateDnsLinkStorage 'Microsoft.Network/virtualNetworks/virtualNetworkLinks@2023-02-01' = {
  name: '${privateDnsZoneStorage.name}-${vnetName}'
  parent: privateDnsZoneStorage
  properties: {
    virtualNetwork: {
      id: resourceId('Microsoft.Network/virtualNetworks', vnetName)
    }
    registrationEnabled: false
  }
}

resource privateDnsLinkCosmos 'Microsoft.Network/virtualNetworks/virtualNetworkLinks@2023-02-01' = {
  name: '${privateDnsZoneCosmos.name}-${vnetName}'
  parent: privateDnsZoneCosmos
  properties: {
    virtualNetwork: {
      id: resourceId('Microsoft.Network/virtualNetworks', vnetName)
    }
    registrationEnabled: false
  }
}

// App Service Plan
resource appServicePlan 'Microsoft.Web/serverfarms@2022-03-01' = {
  name: appServicePlanName
  location: location
  sku: {
    name: 'EP1'
    tier: 'ElasticPremium'
    capacity: 1
  }
}

// Function App
resource functionApp 'Microsoft.Web/sites@2022-09-01' = {
  name: functionAppName
  location: location
  kind: 'functionapp'
  properties: {
    serverFarmId: appServicePlan.id
    siteConfig: {
      alwaysOn: true
      vnetRouteAllEnabled: true
      appSettings: [
        {
          name: 'AzureWebJobsStorage'
          value: storageAccount.properties.primaryEndpoints.blob
        }
        {
          name: 'WEBSITE_VNET_ROUTE_ALL'
          value: '1'
        }
        {
          name: 'WEBSITE_RUN_FROM_PACKAGE'
          value: '1'
        }
      ]
    }
  }
}

output functionAppUrl string = 'https://${functionApp.properties.defaultHostName}'
