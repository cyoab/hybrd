# Apple StoreKit trust root

`AppleRootCA-G3.cer` is the public DER root obtained from:
https://www.apple.com/certificateauthority/AppleRootCA-G3.cer

Source of trust: Apple's PKI publication, not certificate material supplied by a client. The official App Store Server Library uses it to verify signed data and performs online certificate-status checks. This is public certificate material, not a private key. Review root updates explicitly. Configure comma-separated absolute certificate paths if additional Apple roots are required by your deployment.
