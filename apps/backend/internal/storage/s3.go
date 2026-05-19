package storage

import (
	"context"
	"fmt"
	"io"

	"github.com/aws/aws-sdk-go-v2/aws"
	awsconfig "github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/credentials"
	"github.com/aws/aws-sdk-go-v2/service/s3"
)

// Client wraps aws-sdk-go-v2's S3 client. Works against MinIO locally and Cloudflare R2 / AWS S3 in prod.
type Client struct {
	s3       *s3.Client
	bucket   string
	endpoint string
}

type Options struct {
	Endpoint      string
	AccessKey     string
	SecretKey     string
	Bucket        string
	Region        string
	UsePathStyle  bool
}

func New(ctx context.Context, opts Options) (*Client, error) {
	cfg, err := awsconfig.LoadDefaultConfig(ctx,
		awsconfig.WithRegion(opts.Region),
		awsconfig.WithCredentialsProvider(credentials.NewStaticCredentialsProvider(opts.AccessKey, opts.SecretKey, "")),
	)
	if err != nil {
		return nil, fmt.Errorf("aws config: %w", err)
	}
	client := s3.NewFromConfig(cfg, func(o *s3.Options) {
		if opts.Endpoint != "" {
			o.BaseEndpoint = aws.String(opts.Endpoint)
		}
		o.UsePathStyle = opts.UsePathStyle
	})
	return &Client{s3: client, bucket: opts.Bucket, endpoint: opts.Endpoint}, nil
}

// Put uploads an object and returns the key.
func (c *Client) Put(ctx context.Context, key string, body io.Reader, contentType string) error {
	_, err := c.s3.PutObject(ctx, &s3.PutObjectInput{
		Bucket:      aws.String(c.bucket),
		Key:         aws.String(key),
		Body:        body,
		ContentType: aws.String(contentType),
	})
	return err
}

// Get returns a stream for an object key. Caller must Close the body.
func (c *Client) Get(ctx context.Context, key string) (io.ReadCloser, string, error) {
	out, err := c.s3.GetObject(ctx, &s3.GetObjectInput{
		Bucket: aws.String(c.bucket),
		Key:    aws.String(key),
	})
	if err != nil {
		return nil, "", err
	}
	ct := ""
	if out.ContentType != nil {
		ct = *out.ContentType
	}
	return out.Body, ct, nil
}

// PublicURL returns a path-style URL for the given key (for MinIO local dev / R2 when bucket is public).
func (c *Client) PublicURL(key string) string {
	return fmt.Sprintf("%s/%s/%s", c.endpoint, c.bucket, key)
}

// EnsureBucket creates the bucket if it doesn't exist (used in local dev init).
func (c *Client) EnsureBucket(ctx context.Context) error {
	_, err := c.s3.HeadBucket(ctx, &s3.HeadBucketInput{Bucket: aws.String(c.bucket)})
	if err == nil {
		return nil
	}
	_, err = c.s3.CreateBucket(ctx, &s3.CreateBucketInput{Bucket: aws.String(c.bucket)})
	return err
}
