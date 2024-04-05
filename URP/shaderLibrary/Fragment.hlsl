#ifndef FRAGMENT_INCLUDED
#define FRAGMENT_INCLUDED

TEXTURE2D(_CameraColorTexture);
SAMPLER(sampler_CameraColorTexture);
TEXTURE2D(_CameraDepthTexture);

float4 _CameraDepthTexture_TexelSize;
float4 _CameraBufferSize;	//��ʹ����Ⱦ����ʱ��_ScreenParams����ƥ�䵱ǰ�ֱ��ʣ�����������Լ�����һ��

struct Fragment {
	float2 position;
	float2 screenUV;
	float depth;
	float bufferDepth;
};

Fragment GetFragment(float4 position) {
	Fragment f;
	f.position = position.xy;
	//f.screenUV = f.position / _ScreenParams.xy;
	f.screenUV = f.position * _CameraBufferSize.xy;
	f.depth = isOrthographicCamera() ? orthographicDepthBufferToLinear(position.z) : position.w;	//��������ռ����
	f.bufferDepth = SAMPLE_DEPTH_TEXTURE_LOD(_CameraDepthTexture, sampler_point_clamp, f.screenUV, 0);
	//ԭ����պкͷ�͸�����������ռ�����
	f.bufferDepth = isOrthographicCamera() ? orthographicDepthBufferToLinear(f.bufferDepth) : LinearEyeDepth(f.bufferDepth, _ZBufferParams);
	return f;
}

float4 getBufferColor(Fragment fragment, float2 uvOffset = float2(0.0, 0.0)) {
	float2 uv = fragment.screenUV + uvOffset;
	return SAMPLE_TEXTURE2D_LOD(_CameraColorTexture, sampler_CameraColorTexture, uv, 0);
}

#endif