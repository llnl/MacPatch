import requests
from . import _get_token_from_cache
from typing import List

def get(url: str, auth_config: dict, timeout: int = 180) -> requests.Response:
    """Performs a GET on the provided url and returns the result as json

    Args:
        url (str): url to GET
        auth_config: dict containing auth config. Must contain keys:
            TENANT: AAD tenant aka directory, can be guid or name
            CLIENT_ID: Your application's client id aka "applicationID"
            CLIENT_SECRET: Your application's client secret aka "applicationKey"
            HTTPS_SCHEME: either 'https' or 'http', should always be 'https' in production
        timeout (int): number of seconds to wait for connect and read timeout, default 180

    Returns:
        response (requests.Response): response

    """
    required_keys = {
        'TENANT', 
        'CLIENT_ID',
        'CLIENT_SECRET',
        'HTTPS_SCHEME'
    }
    intersection = required_keys & auth_config.keys()
    if len(intersection) != len(required_keys):
        missing_keys = required_keys - intersection
        raise ValueError('auth_config dict missing required keys: ' + ','.join(missing_keys))      
    
    token = get_token(auth_config=auth_config)
    headers = {'Authorization': f'Bearer {token["access_token"]}', 'Accept': 'application/json'}
    response = requests.get(url, headers=headers, timeout=timeout)
    response.raise_for_status()
    return response


def get_token(auth_config: dict, scope: List[str] = None) => dict:
    """Get a token to use in self rolled requests
    
    Example:
        from blueprints.auth.functions import get_token
        token = get_token(auth_config)
        response = requests.get(url, headers={'Authorization': f'Bearer {token["access_token"]}'})

    Args:
        auth_config: dict containing auth config. Must contain keys:
            TENANT: AAD tenant aka directory, can be guid or name
            CLIENT_ID: Your application's client id aka "applicationID"
            CLIENT_SECRET: Your application's client secret aka "applicationKey"
            HTTPS_SCHEME: either 'https' or 'http', should always be 'https' in production
        scope: default ['User.Read'] is enough to get user roles for your app reg
    
    Returns:
        token (dict): A dict with key 'access_token' for use in Bearer header of request
    """
    required_keys = {
        'TENANT', 
        'CLIENT_ID',
        'CLIENT_SECRET',
        'HTTPS_SCHEME'
    }
    intersection = required_keys & auth_config.keys()
    if len(intersection) != len(required_keys):
        missing_keys = required_keys - intersection
        raise ValueError('auth_config dict missing required keys: ' + ','.join(missing_keys))      
    
    scope = scope or ['User.Read']
    token = _get_token_from_cache(auth_config=auth_config, scope=scope)
    return token