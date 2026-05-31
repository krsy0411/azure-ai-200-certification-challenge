/** @type {import('next').NextConfig} */
const nextConfig = {
  // standalone 출력 — Docker 이미지 슬림화에 유리
  // 자세한 내용: https://nextjs.org/docs/pages/api-reference/next-config-js/output
  output: "standalone",

  // 컨테이너 환경에서 React Strict Mode 활성화
  reactStrictMode: true,

  // 운영 환경의 X-Powered-By 헤더 제거
  poweredByHeader: false,
};

export default nextConfig;
