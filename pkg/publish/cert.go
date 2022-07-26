package publish

import (
	"crypto/x509"
	"encoding/pem"
	"fmt"
	"sort"

	"github.com/acorn-io/baaah/pkg/router"
	"github.com/sirupsen/logrus"
	corev1 "k8s.io/api/core/v1"
	networkingv1 "k8s.io/api/networking/v1"
	"sigs.k8s.io/controller-runtime/pkg/client"
)

type TLSCert struct {
	Certificate x509.Certificate `json:"certificate,omitempty"`
	SecretName  string           `json:"secret-name,omitempty"`
}

func (cert *TLSCert) certForThisDomain(name string) bool {
	if valid := cert.Certificate.VerifyHostname(name); valid == nil {
		return true
	}
	return false
}

func convertTLSSecretToTLSCert(secret corev1.Secret) (*TLSCert, error) {
	cert := &TLSCert{}

	tlsPEM, ok := secret.Data["tls.crt"]
	if !ok {
		return nil, fmt.Errorf("key tls.crt not found in secret %s", secret.Name)
	}

	tlsCertBytes, _ := pem.Decode(tlsPEM)
	if tlsCertBytes == nil {
		return nil, fmt.Errorf("failed to parse Cert PEM stored in secret %s", secret.Name)
	}

	tlsDataObj, err := x509.ParseCertificate(tlsCertBytes.Bytes)
	if err != nil {
		return nil, err
	}

	cert.SecretName = secret.Name
	cert.Certificate = *tlsDataObj

	return cert, nil
}

func getCerts(req router.Request, namespace string) ([]*TLSCert, error) {
	var (
		result  []*TLSCert
		secrets corev1.SecretList
	)

	err := req.List(&secrets, &client.ListOptions{
		Namespace: namespace,
	})
	if err != nil {
		return result, err
	}

	for _, secret := range secrets.Items {
		if secret.Type != corev1.SecretTypeTLS {
			continue
		}
		cert, err := convertTLSSecretToTLSCert(secret)
		if err != nil {
			logrus.Errorf("Error processing TLScertificate in secret %s/%s. Recieved %s", secret.Namespace, secret.Name, err)
			continue
		}

		result = append(result, cert)
	}

	sort.Slice(result, func(i, j int) bool {
		return result[i].SecretName < result[j].SecretName
	})

	return result, nil
}

func getCertsForPublishedHosts(rules []networkingv1.IngressRule, certs []*TLSCert) (ingressTLS []networkingv1.IngressTLS) {
	certSecretToHostMapping := map[string][]string{}
	for _, rule := range rules {
		for _, cert := range certs {
			// Find the first cert and stop looking
			if cert.certForThisDomain(rule.Host) {
				certSecretToHostMapping[cert.SecretName] = append(certSecretToHostMapping[cert.SecretName], rule.Host)
				break
			}
		}
	}
	for secret, hosts := range certSecretToHostMapping {
		ingressTLS = append(ingressTLS, networkingv1.IngressTLS{
			Hosts:      hosts,
			SecretName: secret,
		})
	}
	return
}