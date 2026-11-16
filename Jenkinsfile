pipeline {
    agent any

    options {
        timestamps()
    }

    environment {
        TF_IMAGE = 'hashicorp/terraform:1.16.7'
        // plan runs Terragrunt (the layers get their backend, provider and dependencies from it)
        TG_IMAGE = 'alpine/terragrunt:1.15.9'
        TF_CACHE = '/var/lib/jenkins/tf-plugin-cache'
    }

    stages {
        // Check that every .tf file is formatted the standard way (terraform fmt -check). Changes nothing.
        stage('Format') {
            steps {
                // for each layer do "fmt -check -diff"
                sh 'scripts/tf.sh all fmt'
            }
        }

        // The result goes into LAYERS; the later stages loop over it.
        stage('Select layers') {
            steps {
                script {
                    // Merge request: compare with its target branch. Main: everything. Other branches: compare with main.
                    def base = env.CHANGE_TARGET ? "origin/${env.CHANGE_TARGET}" : (env.BRANCH_NAME == 'main' ? 'all' : 'origin/main')
                    env.LAYERS = sh(script: "scripts/tf-layers.sh ${base}", returnStdout: true).trim().replaceAll('\n', ' ')
                    echo "Layers to check: ${env.LAYERS ?: 'none'}"
                }
            }
        }

        // For each selected layer: init, then validate. Catches broken references and wrong arguments.
        stage('Validate') {
            when { expression { env.LAYERS } }
            steps {
                sh '''
                    set -e
                    for l in $LAYERS; do
                        scripts/tf.sh "$l" check
                    done
                '''
            }
        }

        // tflint with the AWS rules from .tflint.hcl: wrong instance types, unused declarations.
        stage('Lint') {
            when { expression { env.LAYERS } }
            steps {
                sh '''
                set -e
                for l in $LAYERS; do
                    echo "=== lint $l"
                    scripts/tf.sh "$l" lint
                done
            '''
            }
        }

        // Trivy security scan of our own code. Report-only: it prints findings but does not fail the build.
        stage('Scan') {
            when { expression { env.LAYERS } }
            steps {
                sh '''
                set -e
                for l in $LAYERS; do
                    echo "=== scan $l"
                scripts/tf.sh "$l" scan
                done
            '''
            }
        }

        // Read-only terragrunt plan against the real state. Assumes the role weatherapp-ci-plan; never applies.
        stage('Plan') {
            when { allOf { expression { env.LAYERS }; changeRequest() } }
            environment {
                TF_PLAN_ROLE_ARN = 'arn:aws:iam::<AWS_ACCOUNT_ID>:role/weatherapp-ci-plan'
                TF_VARS_DIR      = '/var/lib/jenkins/tf-vars'
            }
            steps {
                sh '''
            set -e
            for l in $LAYERS; do
                [ "$l" = 00-bootstrap ] && continue
                echo "=== plan $l"
                scripts/tf.sh "$l" plan
            done
        '''
            }
        }
    }
    post {
        always {
            deleteDir()
        }
    }
}
