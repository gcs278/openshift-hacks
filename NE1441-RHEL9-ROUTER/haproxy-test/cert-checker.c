#include <stdio.h>
#include <stdlib.h>
#include <openssl/ssl.h>
#include <openssl/err.h>

void handle_openssl_error() {
    ERR_print_errors_fp(stderr);
    exit(EXIT_FAILURE);
}

int main(int argc, char *argv[]) {
    if (argc != 2) {
        fprintf(stderr, "Usage: %s <certificate.pem>\n", argv[0]);
        return EXIT_FAILURE;
    }

    const char *cert_file = argv[1];
    SSL_CTX *ctx;

    // Initialize OpenSSL
    SSL_library_init();
    OpenSSL_add_all_algorithms();
    SSL_load_error_strings();

    // Create a new SSL_CTX
    ctx = SSL_CTX_new(TLS_method());
    if (!ctx) {
        fprintf(stderr, "Error creating SSL context.\n");
        handle_openssl_error();
    }

    // Load the certificate
    if (SSL_CTX_use_certificate_file(ctx, cert_file, SSL_FILETYPE_PEM) <= 0) {
        fprintf(stderr, "Failed to load certificate from file: %s\n", cert_file);
        handle_openssl_error();
    } else {
        printf("Certificate loaded successfully from %s\n", cert_file);
    }

    // Cleanup
    SSL_CTX_free(ctx);
    return EXIT_SUCCESS;
}

