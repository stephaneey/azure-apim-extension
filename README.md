# azure-apim-extension
Full Azure API Management suite and more VSTS extension
# Disclaimer
This software is provided as-is with no warranty of anhy kind. 
# API Management Suite in a nutshell
The purpose of this extension is to bring Azure API Management into VSTS as part of your release lifecyle. Whether you use API Management to monetize APIS or for internal purposes, it
is good to associate the release of your backends APIs with their corresponding facade APIs published against the API Gateway. On top of the API Management integration, the extension also 
ships with an API Security Checker that helps validating that all endpoints of an API are well secured, this is of course only applicable to non-public APIs.
# Release Notes
## v1.0
* Supports versioned APIs
* Creation of API products on the fly
* Supports both API and Product policies
* Supports the creation of APIs on top of Azure Functions
* API Security checker


# setup prerequisites and considerations
In order to use this extension, you must have an ARM Service Endpoint configured in VSTS and make sure this endpoint is allowed to contribute to API Management instances. This can easily 
be done by granting Subscription Contributor role or the ad-hoc API Management Service Contributor role. Depending of your usage of API Management, some extra considerations should also be 
paid attention to. If your backend APIs are part of a dedicated VNET, make sure the VSTS agents have connectivity to them. The extension makes use of Swagger import and downloads the Swagger
definition of the backend API. Therefore, connectivity between the VSTS agent and the target API is required.

# tasks included in the extension
## API Management - Create or update product
## API Management - Create or update API
## API Management - Create or update versioned API
## API Management - Create or update API against Azure Functions
## API Management - Create or update versioned API against Azure Functions
## API Security Checker 



