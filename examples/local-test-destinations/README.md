# local-test-destinations

Template for using the library to send data to a test destinations inside the cluster.  
Application monitoring is based on the default ServiceMonitor only.  

Deployment schema: first apply `setup.jsonnet` then `test-instances.jsonnet` and finally `monitoring.jsonnet`
