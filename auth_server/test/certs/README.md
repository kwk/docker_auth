# Creation of example certificates

# Certificate and key for the auth server

The `auth.crt` and `auth.key` files have been created using this command:

```
openssl req -newkey rsa:4096 -nodes -sha256 -keyout auth.key -x509 -days 365 -out auth.crt
Generating a 4096 bit RSA private key
................................................................................................................................................................................................................++
........................................................................++
writing new private key to 'auth.key'
-----
You are about to be asked to enter information that will be incorporated
into your certificate request.
What you are about to enter is what is called a Distinguished Name or a DN.
There are quite a few fields but you can leave some blank
For some fields there will be a default value,
If you enter '.', the field will be left blank.
-----
Country Name (2 letter code) [AU]:DE
State or Province Name (full name) [Some-State]:Example State
Locality Name (eg, city) []:Example City 
Organization Name (eg, company) [Internet Widgits Pty Ltd]:Example Company
Organizational Unit Name (eg, section) []:Example Organizational Unit
Common Name (e.g. server FQDN or YOUR name) []:auth.example.com
Email Address []:admin@auth.example.com
```

# How to list the contents of one of the certificates

```bash
openssl x509 -in auth.crt -text
```
